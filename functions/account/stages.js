// The staged teardown an account-deletion outbox row walks.
//
// Every stage is IDEMPOTENT, BOUNDED (one page per call, cursor persisted on
// the row) and advances only after its own work is empty. A stage that needs
// another page keeps its name and its cursor; the worker brings it straight
// back. Nothing here decides when to run — that is functions/account/deletion.js.
//
// Ordering is the whole safety argument. `auth` is second to last because the
// uid is the only reliable key to everything else: deleting the Auth identity
// early converts a retryable failure into an unrecoverable one. `finalize`
// removes `users/{uid}` itself, which is what stops the deployed trigger's
// retirement merge from keeping an e-mail address forever.
//
// THREE DELIBERATE DEVIATIONS from the design draft, each with its reason:
//
//  1. Reel and Voice Moment media is deleted by STORAGE PREFIX here, not by
//     enqueuing `reelCleanupOutbox` rows. The deployed reel-cleanup worker is
//     the 2026-09-08 revision and dead-letters `kind:"reelVoiceComment"`, and
//     its exports are in the docs/DEPLOYMENT.md forbidden set — routing
//     through it would leave recorded voice bytes in Storage forever.
//  2. A deleted user's direct messages are NOT re-authored to a tombstone uid.
//     `functions/messaging/direct_integrity.js` fails `data-loss` when a
//     message's `senderId` is not one of the two participants, so a tombstone
//     author would break read receipts and reactions for the SURVIVING user.
//     Only the conversation root's identity maps are anonymized.
//  3. Server/club membership is ANONYMIZED, not torn down. Removing a member
//     row correctly needs the Servers operations layer (authorization
//     revisions, channel grants, convergence bindings, the membership outbox
//     and both counters); duplicating that here would either desynchronise a
//     live server or brick one whose owner deleted their account. Ownership
//     succession is still an open owner decision. The deleted user's NAME and
//     PHOTO are replaced with the sentinel identity the fan-out already uses,
//     so no personal data remains — only the pseudonymous uid, which the
//     retained set names explicitly.

const { isValidOpaqueUid } = require("../achievements/identity");
const {
  deletedAccountEmailDigest,
  deletedReportId,
  deletedReporterId,
} = require("./retention");
const { STAGE_ORDER } = require("./outbox");

// UIDs are opaque and case-sensitive. Never trim, lowercase or truncate one —
// any normalization could alias two Auth accounts onto the same teardown.
function canonicalUid(value) {
  return isValidOpaqueUid(value) ? value : null;
}

// The sentinel identity `functions/profile/fanout.js` already writes into
// denormalized contracts. Reusing it means zero schema change: the exact-key
// validators in direct_integrity.js and the Servers member contract keep
// passing, and the string is already non-empty and under the 80-character cap
// every denormalized name field enforces.
const DELETED_IDENTITY_NAME = "YO Voice user";

// The sixteen private subcollections of `users/{uid}`, from firestore.rules.
// Six carry a reciprocal edge in somebody else's document and are handled by
// their own steps; the rest are a plain bounded batch delete.
const RECIPROCAL_SUBCOLLECTIONS = Object.freeze([
  "friends",
  "following",
  "followers",
  "friendRequests",
  "sentFriendRequests",
  "serverFollows",
]);
const PLAIN_SUBCOLLECTIONS = Object.freeze([
  "blocked",
  "muted",
  "momentViews",
  "reelViews",
  "clubs",
  "serverChannelRefs",
  "serverInviteRefs",
  "notifications",
  "incomingCalls",
  "fcmTokens",
]);
const USER_SUBCOLLECTIONS = Object.freeze([
  ...RECIPROCAL_SUBCOLLECTIONS,
  ...PLAIN_SUBCOLLECTIONS,
]);

// uid-keyed top-level documents. `billingAccounts` is deliberately ABSENT:
// the Stripe tombstone contract owns it (functions/premium/stripe_billing.js)
// and the retained set names it. `integrityOperationLedgers` is absent for the
// same kind of reason — deleting a replay guard early re-opens the operation
// it guards.
const UID_KEYED_DOCUMENTS = Object.freeze([
  "publicProfiles",
  "socialPresence",
  "publicBadges",
  "userDirectory",
  "marketingConsents",
  "entitlements",
  "restrictions",
  "vipGrants",
  "directPrivacyPreferences",
  "directCallLocks",
  "activeVoiceSessions",
  "momentCapacityLedgers",
  "clubOwnershipGuards",
  "privateRoomHostGuards",
  "gifRateLimits",
  "reportLimits",
  "serverBroadcastUsage",
  "profileMedia",
  "creatorPinnedPosts",
  "achievementProgress",
  "achievementMigrations",
  "billingCheckoutLocks",
  "serverFamilyOwnerReservations",
]);

// Every Storage prefix owned by exactly one uid (storage.rules).
//
// storage.rules declares ELEVEN top-level prefixes. Seven of them begin with a
// uid, and those seven are this list. THE OTHER FOUR ARE NOT SWEPT BY THIS
// PIPELINE AT ALL, and the disclosure below is the complete one — an earlier
// revision of this comment named only the first two, which made the gap look
// half the size it is:
//
//   1. family_moments/{clubId}/{userId}/          (storage.rules:321)
//   2. server_company_files/{serverId}/{channelId}/{userId}/
//                                                 (storage.rules:434)
//      — uid-keyed, but UNDER somebody else's container, so a prefix delete
//        keyed on the uid cannot reach them. Closing these two needs an
//        enumeration of the club/server ids the social stage already walks.
//   3. room_images/{roomId}/{fileName}            (storage.rules:165)
//      — a room cover. The uploader is identifiable (the object is named
//        `{uid}_{32 hex}.jpg|png` and its custom metadata carries `ownerId`)
//        but NOTHING in the path is the uid, so no prefix delete reaches it.
//        Closing this needs an enumeration of the rooms the account hosted,
//        or a per-object metadata scan.
//   4. server_podcast_episodes/{serverId}/{channelId}/{fileName}
//                                                 (storage.rules:506)
//      — `allow read, write: if false`: written only by the backend, keyed by
//        neither uid nor uploader anywhere in the path or the object name.
//        There is no uid-derived handle on it to delete.
//
// This list is therefore exactly seven fixed prefixes and nothing more. The
// gap is tracked in docs/Bugs.md ("Account deletion leaves cross-container
// Storage objects", 2026-09-18), mirrored in the public /delete-account
// "what deleting your account does not do" section, and NO user-facing copy
// claims any of the four categories is removed — see ADR-206's Consequences.
// If you add a prefix to storage.rules, this comment and that copy are part
// of the change.
function uidStoragePrefixes(uid) {
  return Object.freeze([
    `users/${uid}/profile/`,
    `voice_moments/${uid}/`,
    `voice_replies/${uid}/`,
    `reel_voice_comments/${uid}/`,
    `reels/${uid}/`,
    `message_attachments/${uid}/`,
    `clubs/${uid}/`,
  ]);
}

const DEFAULT_LIMITS = Object.freeze({
  edgePage: 25,
  plainPage: 200,
  contentPage: 10,
  conversationPage: 50,
  reportPage: 25,
  serverPage: 25,
  storagePrefixesPerCall: 3,
});

function resolveLimits(overrides = {}) {
  const limits = { ...DEFAULT_LIMITS, ...overrides };
  for (const [key, value] of Object.entries(limits)) {
    if (!Number.isSafeInteger(value) || value < 1 || value > 500) {
      throw new TypeError(`Account deletion limit ${key} is invalid.`);
    }
  }
  return Object.freeze(limits);
}

function cursorStep(cursor) {
  const step = cursor?.step;
  return Number.isSafeInteger(step) && step >= 0 ? step : 0;
}

function safeCount(value) {
  return Number.isSafeInteger(value) && value > 0 ? value : 0;
}

function isNotFound(error) {
  const code = typeof error?.code === "string" ? error.code : "";
  return code === "auth/user-not-found" ||
    code === "auth/invalid-uid" ||
    error?.errorInfo?.code === "auth/user-not-found";
}

/**
 * Builds the stage runner.
 *
 * Every dependency is injected so the suites can drive a stage directly and
 * so the Storage bucket stays lazy — resolving it at module load would pull
 * @google-cloud/storage into every cold start, which
 * test/cold_start_module_graph.test.js pins at zero.
 */
function createAccountDeletionStages({
  db,
  FieldValue,
  FieldPath,
  authAdmin,
  resolveBucket,
  deleteTrustedPrefix,
  logger = console,
  limits: limitOverrides = {},
  environment = process.env,
} = {}) {
  if (!db || typeof db.collection !== "function") {
    throw new TypeError("A Firestore database is required.");
  }
  if (!FieldValue || !FieldPath) {
    throw new TypeError("Firestore field helpers are required.");
  }
  if (typeof resolveBucket !== "function" ||
      typeof deleteTrustedPrefix !== "function") {
    throw new TypeError("A Storage bucket resolver is required.");
  }
  const limits = resolveLimits(limitOverrides);

  async function deletePage(query) {
    const snapshot = await query.get();
    if (snapshot.empty) return { size: 0, docs: [] };
    const batch = db.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
    return { size: snapshot.size, docs: snapshot.docs };
  }

  // ---------------------------------------------------------------- revoke

  async function runRevoke(uid) {
    try {
      await authAdmin.revokeRefreshTokens(uid);
    } catch (error) {
      if (!isNotFound(error)) throw error;
    }
    // Live call and voice-session state is the only thing that can still act
    // on a frozen account, so it goes first and is deleted, not anonymized.
    await Promise.all([
      db.recursiveDelete(db.collection("activeVoiceSessions").doc(uid)),
      db.collection("directCallLocks").doc(uid).delete(),
    ]);
    return { done: true, cursor: null, details: { revoked: true } };
  }

  // --------------------------------------------------------------- content

  async function runContent(uid) {
    let removed = 0;
    for (const collectionName of ["voiceMoments", "reels"]) {
      const snapshot = await db
        .collection(collectionName)
        .where("authorId", "==", uid)
        .limit(limits.contentPage)
        .get();
      for (const document of snapshot.docs) {
        // recursiveDelete takes the comments and likes subcollections with
        // the root. The bytes are removed by the `storage` stage, whose
        // prefixes cover every object these rows can name.
        await db.recursiveDelete(document.ref);
        removed += 1;
      }
      if (snapshot.size >= limits.contentPage) {
        return { done: false, cursor: null, details: { removed } };
      }
    }
    return { done: true, cursor: null, details: { removed } };
  }

  // ---------------------------------------------------------------- social

  async function removeFriendEdges(uid) {
    const snapshot = await db
      .collection("users").doc(uid).collection("friends")
      .limit(limits.edgePage).get();
    for (const document of snapshot.docs) {
      const peer = canonicalUid(document.id);
      if (!peer) {
        await document.ref.delete();
        continue;
      }
      const peerReference = db.collection("users").doc(peer);
      // Edge and counter in ONE transaction, exactly like the social-graph
      // callables: a partial batch drifts the peer's friendCount permanently.
      await db.runTransaction(async (transaction) => {
        const peerSnapshot = await transaction.get(peerReference);
        transaction.delete(document.ref);
        transaction.delete(peerReference.collection("friends").doc(uid));
        transaction.delete(
          db.collection("friendshipGuards").doc(uid)
            .collection("friends").doc(peer),
        );
        transaction.delete(
          db.collection("friendshipGuards").doc(peer)
            .collection("friends").doc(uid),
        );
        if (peerSnapshot.exists) {
          const current = safeCount(peerSnapshot.data()?.friendCount);
          transaction.update(peerReference, {
            friendCount: Math.max(0, current - 1),
          });
        }
      });
    }
    return snapshot.size;
  }

  async function removeFollowEdges(uid, { side }) {
    const own = side === "following" ? "following" : "followers";
    const mirror = side === "following" ? "followers" : "following";
    const counter = side === "following" ? "followerCount" : "followingCount";
    const snapshot = await db
      .collection("users").doc(uid).collection(own)
      .limit(limits.edgePage).get();
    for (const document of snapshot.docs) {
      const peer = canonicalUid(document.id);
      if (!peer) {
        await document.ref.delete();
        continue;
      }
      const peerReference = db.collection("users").doc(peer);
      await db.runTransaction(async (transaction) => {
        const peerSnapshot = await transaction.get(peerReference);
        transaction.delete(document.ref);
        transaction.delete(peerReference.collection(mirror).doc(uid));
        if (peerSnapshot.exists) {
          const current = safeCount(peerSnapshot.data()?.[counter]);
          transaction.update(peerReference, {
            [counter]: Math.max(0, current - 1),
          });
        }
      });
    }
    return snapshot.size;
  }

  async function removeRequestEdges(uid, { own, mirror }) {
    const snapshot = await db
      .collection("users").doc(uid).collection(own)
      .limit(limits.edgePage).get();
    if (snapshot.empty) return 0;
    const batch = db.batch();
    for (const document of snapshot.docs) {
      batch.delete(document.ref);
      const peer = canonicalUid(document.id);
      if (peer) {
        batch.delete(
          db.collection("users").doc(peer).collection(mirror).doc(uid),
        );
      }
    }
    await batch.commit();
    return snapshot.size;
  }

  async function removeServerFollows(uid) {
    const snapshot = await db
      .collection("users").doc(uid).collection("serverFollows")
      .limit(limits.edgePage).get();
    if (snapshot.empty) return 0;
    const batch = db.batch();
    for (const document of snapshot.docs) {
      batch.delete(document.ref);
      const serverId = canonicalUid(document.id);
      if (serverId) {
        batch.delete(
          db.collection("clubs").doc(serverId)
            .collection("followers").doc(uid),
        );
      }
    }
    await batch.commit();
    return snapshot.size;
  }

  /**
   * Replaces the deleted user's denormalized identity inside every server they
   * belong to, and on every server they own.
   *
   * Membership itself is preserved on purpose (see the header). The write is a
   * field-level merge of exactly the two identity fields, so the Servers member
   * contract's key set is untouched.
   */
  async function anonymizeServerIdentity(uid, cursor) {
    const startAfter = typeof cursor?.serverId === "string"
      ? cursor.serverId
      : null;
    let query = db
      .collection("users").doc(uid).collection("clubs")
      .orderBy(FieldPath.documentId())
      .limit(limits.serverPage);
    if (startAfter) query = query.startAfter(startAfter);
    const snapshot = await query.get();
    let lastId = startAfter;
    for (const document of snapshot.docs) {
      lastId = document.id;
      const serverId = canonicalUid(document.id);
      if (!serverId) continue;
      const serverReference = db.collection("clubs").doc(serverId);
      const memberReference = serverReference.collection("members").doc(uid);
      const [serverSnapshot, memberSnapshot] = await Promise.all([
        serverReference.get(),
        memberReference.get(),
      ]);
      const writes = [];
      if (memberSnapshot.exists) {
        const member = memberSnapshot.data() ?? {};
        if (member.displayName !== DELETED_IDENTITY_NAME ||
            member.photoUrl !== null) {
          writes.push(memberReference.set(
            { displayName: DELETED_IDENTITY_NAME, photoUrl: null },
            { merge: true },
          ));
        }
      }
      if (serverSnapshot.exists &&
          serverSnapshot.data()?.ownerId === uid &&
          serverSnapshot.data()?.ownerName !== DELETED_IDENTITY_NAME) {
        writes.push(serverReference.set(
          { ownerName: DELETED_IDENTITY_NAME },
          { merge: true },
        ));
      }
      if (writes.length > 0) await Promise.all(writes);
    }
    return {
      size: snapshot.size,
      cursor: snapshot.size >= limits.serverPage && lastId
        ? { serverId: lastId }
        : null,
    };
  }

  const SOCIAL_STEPS = Object.freeze([
    { name: "friends", run: (uid) => removeFriendEdges(uid) },
    { name: "following", run: (uid) => removeFollowEdges(uid, { side: "following" }) },
    { name: "followers", run: (uid) => removeFollowEdges(uid, { side: "followers" }) },
    {
      name: "friendRequests",
      run: (uid) => removeRequestEdges(uid, {
        own: "friendRequests", mirror: "sentFriendRequests",
      }),
    },
    {
      name: "sentFriendRequests",
      run: (uid) => removeRequestEdges(uid, {
        own: "sentFriendRequests", mirror: "friendRequests",
      }),
    },
    { name: "serverFollows", run: (uid) => removeServerFollows(uid) },
  ]);

  async function runSocial(uid, cursor) {
    const step = cursorStep(cursor);

    if (step < SOCIAL_STEPS.length) {
      const removed = await SOCIAL_STEPS[step].run(uid);
      const complete = removed < limits.edgePage;
      return {
        done: false,
        cursor: { step: complete ? step + 1 : step },
        details: { step: SOCIAL_STEPS[step].name, removed },
      };
    }

    const serverStep = SOCIAL_STEPS.length;
    if (step === serverStep) {
      const outcome = await anonymizeServerIdentity(uid, cursor);
      return {
        done: false,
        cursor: outcome.cursor
          ? { step, serverId: outcome.cursor.serverId }
          : { step: step + 1 },
        details: { step: "serverIdentity", scanned: outcome.size },
      };
    }

    const plainIndex = step - serverStep - 1;
    if (plainIndex < PLAIN_SUBCOLLECTIONS.length) {
      const name = PLAIN_SUBCOLLECTIONS[plainIndex];
      const page = await deletePage(
        db.collection("users").doc(uid).collection(name)
          .limit(limits.plainPage),
      );
      const complete = page.size < limits.plainPage;
      return {
        done: false,
        cursor: { step: complete ? step + 1 : step },
        details: { step: name, removed: page.size },
      };
    }

    return { done: true, cursor: null, details: { step: "complete" } };
  }

  // ------------------------------------------------------------- messaging

  async function runMessaging(uid, cursor) {
    const startAfter = typeof cursor?.conversationId === "string"
      ? cursor.conversationId
      : null;
    let query = db
      .collection("conversations")
      .where("participantIds", "array-contains", uid)
      .orderBy(FieldPath.documentId())
      .limit(limits.conversationPage);
    if (startAfter) query = query.startAfter(startAfter);
    const snapshot = await query.get();
    let lastId = startAfter;
    let updated = 0;
    for (const document of snapshot.docs) {
      lastId = document.id;
      const data = document.data() ?? {};
      const names = data.participantNames ?? {};
      const photos = data.participantPhotoUrls ?? {};
      if (names[uid] === DELETED_IDENTITY_NAME && photos[uid] === "") continue;
      // Dotted field paths, so the conversation root's EXACT key set — which
      // direct_integrity.js validates on every read — is unchanged. The name
      // must stay non-empty and <= 80 characters or that validator throws
      // `data-loss` for the surviving participant.
      await document.ref.update({
        [`participantNames.${uid}`]: DELETED_IDENTITY_NAME,
        [`participantPhotoUrls.${uid}`]: "",
      });
      updated += 1;
    }
    if (snapshot.size >= limits.conversationPage && lastId) {
      return {
        done: false,
        cursor: { conversationId: lastId },
        details: { updated },
      };
    }
    return { done: true, cursor: null, details: { updated } };
  }

  // --------------------------------------------------------------- storage

  async function runStorage(uid, cursor) {
    const prefixes = uidStoragePrefixes(uid);
    const index = cursorStep(cursor);
    if (index >= prefixes.length) {
      return { done: true, cursor: null, details: { prefixes: prefixes.length } };
    }
    const bucket = resolveBucket();
    const slice = prefixes.slice(index, index + limits.storagePrefixesPerCall);
    for (const prefix of slice) {
      const outcome = await deleteTrustedPrefix(prefix, bucket);
      if (outcome?.deleted !== true) {
        // Throwing keeps the row retryable with backoff. Advancing past a
        // prefix whose objects survived would make the deletion promise false.
        const error = new Error("Storage prefix deletion did not complete.");
        error.code = "storage-cleanup-incomplete";
        throw error;
      }
    }
    const next = index + slice.length;
    return {
      done: next >= prefixes.length,
      cursor: next >= prefixes.length ? null : { step: next },
      details: { deleted: slice },
    };
  }

  // --------------------------------------------------------------- records

  async function writeBanDigest(uid, row) {
    const snapshot = await db.collection("users").doc(uid).get();
    const profile = snapshot.exists ? (snapshot.data() ?? {}) : {};
    if (profile.banned !== true) {
      return { banDigestWritten: false, banDigestSkipped: false };
    }
    const digest = deletedAccountEmailDigest(profile.email, {
      salt: typeof environment?.YOVOICE_DELETED_ACCOUNT_DIGEST_SALT === "string"
        ? environment.YOVOICE_DELETED_ACCOUNT_DIGEST_SALT.trim()
        : undefined,
    });
    if (!digest) {
      // No salt configured, or no usable e-mail. An UNSALTED digest of an
      // e-mail address is trivially reversible, so nothing is written and the
      // gap is recorded instead of hidden.
      logger.warn?.("account deletion could not write a ban digest", {
        uid,
        reason: "digest-salt-unavailable",
      });
      return { banDigestWritten: false, banDigestSkipped: true };
    }
    await db.collection("deletedAccountDigests").doc(digest).set({
      schemaVersion: 1,
      reason: "ban",
      bannedUntil: profile.bannedUntil ?? null,
      createdAt: FieldValue.serverTimestamp(),
      source: typeof row?.source === "string" ? row.source : "app",
    });
    return { banDigestWritten: true, banDigestSkipped: false };
  }

  async function rekeyFiledReports(uid, tombstone) {
    const snapshot = await db
      .collection("reports")
      .where("reporterId", "==", uid)
      .limit(limits.reportPage)
      .get();
    let moved = 0;
    for (const document of snapshot.docs) {
      const rekeyed = deletedReportId(document.id, uid, tombstone);
      const data = { ...(document.data() ?? {}) };
      data.reporterId = deletedReporterId(tombstone);
      const batch = db.batch();
      if (rekeyed) {
        // A re-key is copy-then-delete because the reporter uid is in the
        // PATH, not only the field; updating in place would leave it there.
        batch.set(db.collection("reports").doc(rekeyed), data);
      } else {
        // An id that does not carry the reporter prefix (a legacy row) still
        // gets the field anonymized rather than being left alone.
        batch.set(document.ref, data);
      }
      if (rekeyed) batch.delete(document.ref);
      await batch.commit();
      moved += 1;
    }
    return { moved, complete: snapshot.size < limits.reportPage };
  }

  /**
   * Strips the e-mail addresses out of `adminAuditLogs` without destroying the
   * audit trail.
   *
   * This is the residue the data-safety research missed and the deletion
   * inventory found: `functions/utils/audit.js` writes `actorEmail` on every
   * staff action and `targetLabel = <the affected user's e-mail>` on every
   * user-scoped one, and today's deletion leaves both in place, in BOTH
   * directions, forever.
   *
   * The trail itself is retained on purpose — an audit log a subject can erase
   * is not an audit log — but `actorId` and `targetId` are pseudonymous uids
   * and carry the accountability on their own. The e-mail carries nothing the
   * uid does not, so it is cleared rather than kept.
   */
  async function anonymizeAuditEmails(uid, cursor, { field, clear }) {
    const startAfter = typeof cursor?.auditId === "string"
      ? cursor.auditId
      : null;
    let query = db
      .collection("adminAuditLogs")
      .where(field, "==", uid)
      .orderBy(FieldPath.documentId())
      .limit(limits.reportPage);
    if (startAfter) query = query.startAfter(startAfter);
    const snapshot = await query.get();
    let lastId = startAfter;
    let cleared = 0;
    const batch = db.batch();
    for (const document of snapshot.docs) {
      lastId = document.id;
      if ((document.data() ?? {})[clear] === null) continue;
      batch.update(document.ref, { [clear]: null });
      cleared += 1;
    }
    if (cleared > 0) await batch.commit();
    return {
      cleared,
      cursor: snapshot.size >= limits.reportPage && lastId
        ? { auditId: lastId }
        : null,
    };
  }

  async function runRecords(uid, cursor, row) {
    const step = cursorStep(cursor);

    if (step === 0) {
      const outcome = await writeBanDigest(uid, row);
      return { done: false, cursor: { step: 1 }, details: outcome };
    }

    if (step === 1) {
      const batch = db.batch();
      for (const name of UID_KEYED_DOCUMENTS) {
        batch.delete(db.collection(name).doc(uid));
      }
      await batch.commit();
      // profileMedia carries per-uid subcollections of reservations and
      // finalizations; the bounded recursive delete removes both.
      await Promise.all([
        db.recursiveDelete(db.collection("profileMedia").doc(uid)),
        db.recursiveDelete(
          db.collection("profileMediaUploadReservations").doc(uid),
        ),
        db.recursiveDelete(
          db.collection("profileMediaFinalizations").doc(uid),
        ),
        db.recursiveDelete(
          db.collection("profileMediaUploadBudgets").doc(uid),
        ),
      ]);
      return {
        done: false,
        cursor: { step: 2 },
        details: { documents: UID_KEYED_DOCUMENTS.length },
      };
    }

    if (step === 2) {
      const tombstone = row?.reporterTombstone;
      const outcome = await rekeyFiledReports(uid, tombstone);
      return {
        done: false,
        cursor: { step: outcome.complete ? 3 : 2 },
        details: { reportsRekeyed: outcome.moved },
      };
    }

    if (step === 3 || step === 4) {
      const target = step === 3
        ? { field: "targetId", clear: "targetLabel" }
        : { field: "actorId", clear: "actorEmail" };
      const outcome = await anonymizeAuditEmails(uid, cursor, target);
      return {
        done: false,
        cursor: outcome.cursor
          ? { step, auditId: outcome.cursor.auditId }
          : { step: step + 1 },
        details: { auditEmailsCleared: outcome.cleared, field: target.clear },
      };
    }

    return { done: true, cursor: null, details: { step: "complete" } };
  }

  // ------------------------------------------------------------------ auth

  /**
   * The one irreversible step. It runs only from the `auth` stage of a row
   * that is not dead-lettered, which the worker asserts before calling in.
   */
  async function runAuth(uid) {
    try {
      await authAdmin.deleteUser(uid);
    } catch (error) {
      if (!isNotFound(error)) throw error;
    }
    return { done: true, cursor: null, details: { authDeleted: true } };
  }

  // -------------------------------------------------------------- finalize

  /**
   * `onAuthUserDeleted` normally performs this write the instant the Auth
   * identity disappears. This is the same two writes, so a lost trigger
   * delivery cannot leave the e-mail-bearing document behind.
   *
   * The `recursiveDelete` runs whether or not `users/{uid}` itself still
   * exists, and that is the whole point of this stage. **In Firestore a
   * subcollection is not owned by its parent document**: `users/{uid}` can be
   * gone while `users/{uid}/friends`, `users/{uid}/blocked` and
   * `users/{uid}/momentViews` are still full of rows, and those rows are
   * personal data about the person being erased. The state is reachable more
   * than one way — `onAuthUserDeleted` deletes the root document by itself the
   * moment the Auth identity goes, the `social` stage can be interrupted after
   * it has emptied some subcollections but before `finalize` runs, a re-run of
   * the sweep finds the document already gone, and an operator backfill may
   * have removed it by hand. Returning early on a missing snapshot therefore
   * did not mean "nothing to do", it meant "orphan these rows permanently":
   * nothing else in the pipeline walks this path again, and no client can
   * reach a subcollection under a document that no longer exists in order to
   * clean it up.
   *
   * The snapshot is still read, but only to report which of the two cases
   * this was. `subcollections` records that the descendant sweep ran either
   * way, so an outbox row can be read back and the distinction seen.
   */
  async function runFinalize(uid) {
    const reference = db.collection("users").doc(uid);
    const snapshot = await reference.get();
    await db.recursiveDelete(reference);
    return {
      done: true,
      cursor: null,
      details: {
        userDocument: snapshot.exists ? "deleted" : "absent",
        subcollections: "deleted",
      },
    };
  }

  const RUNNERS = Object.freeze({
    revoke: (uid) => runRevoke(uid),
    content: (uid) => runContent(uid),
    social: (uid, cursor) => runSocial(uid, cursor),
    messaging: (uid, cursor) => runMessaging(uid, cursor),
    storage: (uid, cursor) => runStorage(uid, cursor),
    records: (uid, cursor, row) => runRecords(uid, cursor, row),
    auth: (uid) => runAuth(uid),
    finalize: (uid) => runFinalize(uid),
  });

  async function runStage(stage, { uid, cursor = null, row = null } = {}) {
    const runner = RUNNERS[stage];
    if (!runner) {
      const error = new Error(`Unknown account-deletion stage: ${stage}`);
      error.code = "data-loss";
      throw error;
    }
    const cleanUid = canonicalUid(uid);
    if (!cleanUid) {
      const error = new Error("A canonical uid is required.");
      error.code = "data-loss";
      throw error;
    }
    return runner(cleanUid, cursor, row);
  }

  return Object.freeze({
    DELETED_IDENTITY_NAME,
    PLAIN_SUBCOLLECTIONS,
    RECIPROCAL_SUBCOLLECTIONS,
    STAGE_ORDER,
    UID_KEYED_DOCUMENTS,
    USER_SUBCOLLECTIONS,
    limits,
    runStage,
    uidStoragePrefixes,
  });
}

module.exports = {
  DELETED_IDENTITY_NAME,
  DEFAULT_LIMITS,
  PLAIN_SUBCOLLECTIONS,
  RECIPROCAL_SUBCOLLECTIONS,
  STAGE_ORDER,
  UID_KEYED_DOCUMENTS,
  USER_SUBCOLLECTIONS,
  createAccountDeletionStages,
  uidStoragePrefixes,
};
