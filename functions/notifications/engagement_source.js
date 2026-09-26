/**
 * Source validators for the notification types added on 2026-09-19
 * (ADR-213): comments on a Voice Moment or a Yeel, @mentions inside those
 * comments, Server event reminders and Server role promotions.
 *
 * Every function here answers one question — "is the thing this row
 * announces still true, and may this recipient still learn about it?" —
 * and answers it twice: inside the canonical writer's transaction (so a row
 * is never created for a stale source) and inside the push claim
 * transaction (so a source that changed between write and push never
 * pushes). Each returns a boolean and never throws for a refusal, because
 * an HttpsError from a shared guard is a "no", not an infrastructure fault.
 *
 * `reader` is either a Firestore transaction or the Firestore instance;
 * both expose `getAll`, which is the only read method used here.
 */
const { HttpsError } = require("firebase-functions/v2/https");

const {
  activeProfile,
  assertNotBlocked,
  assertNotRestricted,
  isValidOpaqueUid,
  timestampMillis,
} = require("../integrity/guards");
const {
  exactFriendshipGuard,
  profileVisibilityOf,
} = require("../profile/media_contract");
const { ROLE_POWER } = require("../servers/contract");
const {
  commentMentionDocumentId,
  exactCommentMentions,
} = require("./comment_mentions");
const {
  canonicalMember,
  canonicalServer,
  readChannelAccess,
} = require("../servers/authority");

const ENGAGEMENT_NOTIFICATION_TYPES = Object.freeze([
  "momentComment",
  "reelComment",
  "commentMention",
  "serverEventReminder",
  "serverRole",
]);

const SAFE_SEGMENT = /^[A-Za-z0-9_-]{1,128}$/u;

function refusal(operation) {
  try {
    operation();
    return true;
  } catch (_) {
    return false;
  }
}

async function readAll(reader, ...references) {
  return reader.getAll(...references);
}

function commentSourcePath(kind, parentId, commentId) {
  const root = kind === "reel" ? "reels" : "voiceMoments";
  return `${root}/${parentId}/comments/${commentId}`;
}

/** Parses `voiceMoments/{id}/comments/{id}` or `reels/{id}/comments/{id}`. */
function parseCommentSourcePath(path) {
  if (typeof path !== "string") return null;
  const parts = path.split("/");
  if (parts.length !== 4 || parts[2] !== "comments") return null;
  const kind = parts[0] === "voiceMoments"
    ? "moment"
    : parts[0] === "reels" ? "reel" : null;
  if (!kind || !SAFE_SEGMENT.test(parts[1]) || !SAFE_SEGMENT.test(parts[3])) {
    return null;
  }
  return { kind, parentId: parts[1], commentId: parts[3] };
}

/** Parses `clubs/{serverId}/channels/{channelId}/events/{eventId}`. */
function parseServerEventPath(path) {
  if (typeof path !== "string") return null;
  const parts = path.split("/");
  if (parts.length !== 6 || parts[0] !== "clubs" || parts[2] !== "channels" ||
      parts[4] !== "events" || ![1, 3, 5].every((index) =>
        SAFE_SEGMENT.test(parts[index]))) {
    return null;
  }
  return { serverId: parts[1], channelId: parts[3], eventId: parts[5] };
}

/**
 * The Voice Moment audience rule, evaluated for an arbitrary viewer. It is
 * the same decision `assertVoiceMomentAudienceFromContext` makes in
 * moments/integrity.js for a caller: both accounts active and unrestricted,
 * no block in either direction, then the author's profile visibility —
 * public admits everyone, friends admits exact mutual friendship guards,
 * anything else admits only the author.
 */
async function voiceMomentAudienceAllows(reader, firestore, {
  viewerId,
  authorId,
  nowMs,
}) {
  if (!isValidOpaqueUid(viewerId) || !isValidOpaqueUid(authorId)) return false;
  const same = viewerId === authorId;
  const references = [
    firestore.doc(`users/${viewerId}`),
    firestore.doc(`restrictions/${viewerId}`),
    firestore.doc(`users/${authorId}`),
    firestore.doc(`restrictions/${authorId}`),
  ];
  if (!same) {
    references.push(
      firestore.doc(`users/${viewerId}/blocked/${authorId}`),
      firestore.doc(`users/${authorId}/blocked/${viewerId}`),
      firestore.doc(`friendshipGuards/${viewerId}/friends/${authorId}`),
      firestore.doc(`friendshipGuards/${authorId}/friends/${viewerId}`),
    );
  }
  const [
    viewer,
    viewerRestriction,
    author,
    authorRestriction,
    viewerBlock,
    authorBlock,
    forward,
    reverse,
  ] = await readAll(reader, ...references);
  let authorData = null;
  const statesAllow = refusal(() => {
    activeProfile(viewer, "Viewer");
    assertNotRestricted(viewerRestriction, "Viewer", nowMs);
    authorData = activeProfile(author, "Author");
    assertNotRestricted(authorRestriction, "Author", nowMs);
    if (!same) assertNotBlocked(viewerBlock, authorBlock);
  });
  if (!statesAllow) return false;
  if (same) return true;
  const visibility = profileVisibilityOf(authorData);
  if (visibility === "public") return true;
  return visibility === "friends" &&
    exactFriendshipGuard(forward, viewerId, authorId) &&
    exactFriendshipGuard(reverse, authorId, viewerId);
}

function liveMoment(snapshot, momentId, nowMs) {
  // Lazy: moments/integrity.js is a large module and this file is loaded by
  // the push trigger on every cold start.
  const { validateMoment } = require("../moments/integrity");
  let data = null;
  const valid = refusal(() => {
    data = validateMoment(snapshot, momentId, {
      published: true,
      activeAtMs: nowMs,
    });
  });
  return valid ? data : null;
}

function liveMomentComment(snapshot, momentId) {
  const { validateComment } = require("../moments/integrity");
  let data = null;
  const valid = refusal(() => {
    data = validateComment(snapshot, momentId);
  });
  return valid ? data : null;
}

function liveReel(reelSnapshot, availabilitySnapshot, nowMs) {
  if (!reelSnapshot?.exists) return null;
  const reel = reelSnapshot.data() ?? {};
  if (reel.status !== "published" || reel.moderationStatus !== "visible" ||
      !isValidOpaqueUid(reel.authorId) ||
      timestampMillis(reel.publishedAt) === null) {
    return null;
  }
  const { publishedAvailability } = require("../reels/availability");
  const valid = refusal(() => {
    publishedAvailability(
      availabilitySnapshot,
      { ...reel, id: reelSnapshot.id },
      nowMs,
    );
  });
  return valid ? { ...reel, id: reelSnapshot.id } : null;
}

function liveReelComment(snapshot, reelId) {
  const { validateReelComment } = require("../reels/engagement");
  let data = null;
  const valid = refusal(() => {
    data = validateReelComment(snapshot, reelId);
  });
  return valid ? data : null;
}

/**
 * Loads the parent and the comment, and proves both are live: the comment
 * exists, was written by `actorId`, and its parent is published and inside
 * its availability window. Returns the parent's author id, or null.
 */
async function liveCommentParent(reader, firestore, {
  kind,
  parentId,
  commentId,
  actorId,
  nowMs,
}) {
  if (kind === "moment") {
    const [moment, comment] = await readAll(
      reader,
      firestore.doc(`voiceMoments/${parentId}`),
      firestore.doc(commentSourcePath("moment", parentId, commentId)),
    );
    const momentData = liveMoment(moment, parentId, nowMs);
    const commentData = liveMomentComment(comment, parentId);
    if (!momentData || !commentData || commentData.authorId !== actorId) {
      return null;
    }
    return momentData.authorId;
  }
  if (kind === "reel") {
    const [reel, availability, comment] = await readAll(
      reader,
      firestore.doc(`reels/${parentId}`),
      firestore.doc(`reelAvailability/${parentId}`),
      firestore.doc(commentSourcePath("reel", parentId, commentId)),
    );
    const reelData = liveReel(reel, availability, nowMs);
    const commentData = liveReelComment(comment, parentId);
    if (!reelData || !commentData || commentData.authorId !== actorId) {
      return null;
    }
    return reelData.authorId;
  }
  return null;
}

/**
 * Reels have no per-author audience (reels/service.js assertReelAuthorAudience):
 * both accounts active and unrestricted and no block either way. Moments
 * apply the author's profile visibility on top.
 */
async function audienceAllows(reader, firestore, {
  kind,
  viewerId,
  authorId,
  nowMs,
}) {
  if (kind === "moment") {
    return voiceMomentAudienceAllows(reader, firestore, {
      viewerId,
      authorId,
      nowMs,
    });
  }
  if (!isValidOpaqueUid(viewerId) || !isValidOpaqueUid(authorId)) return false;
  const same = viewerId === authorId;
  const [viewer, viewerRestriction, author, authorRestriction, one, two] =
    await readAll(
      reader,
      firestore.doc(`users/${viewerId}`),
      firestore.doc(`restrictions/${viewerId}`),
      firestore.doc(`users/${authorId}`),
      firestore.doc(`restrictions/${authorId}`),
      firestore.doc(`users/${viewerId}/blocked/${authorId}`),
      firestore.doc(`users/${authorId}/blocked/${viewerId}`),
    );
  return refusal(() => {
    activeProfile(viewer, "Viewer");
    assertNotRestricted(viewerRestriction, "Viewer", nowMs);
    activeProfile(author, "Author");
    assertNotRestricted(authorRestriction, "Author", nowMs);
    if (!same) assertNotBlocked(one, two);
  });
}

/**
 * momentComment / reelComment: the recipient is the parent's author, the
 * commenter still sees the parent, and the comment still exists.
 */
async function commentNotificationSourceIsCurrent({
  recipientId,
  notification,
  reader,
  firestore,
  nowMs = Date.now(),
}) {
  const source = parseCommentSourcePath(notification?.sourcePath);
  const expectedKind = notification?.type === "reelComment" ? "reel" : "moment";
  const actorId = notification?.actorId;
  if (!source || source.kind !== expectedKind ||
      notification?.targetId !== source.parentId ||
      !isValidOpaqueUid(actorId) || actorId === recipientId) {
    return false;
  }
  const authorId = await liveCommentParent(reader, firestore, {
    ...source,
    actorId,
    nowMs,
  });
  if (!authorId || authorId !== recipientId) return false;
  return audienceAllows(reader, firestore, {
    kind: source.kind,
    viewerId: actorId,
    authorId,
    nowMs,
  });
}

/**
 * commentMention: the comment still exists, its server-only mention record
 * still names the recipient, the recipient is neither the commenter nor the
 * parent's author (who receives the comment row instead), and — the leak
 * this exists to prevent — the MENTIONED person can see the parent. A
 * friends-only Moment must never announce itself to a non-friend.
 */
async function commentMentionSourceIsCurrent({
  recipientId,
  notification,
  reader,
  firestore,
  nowMs = Date.now(),
}) {
  const source = parseCommentSourcePath(notification?.sourcePath);
  const actorId = notification?.actorId;
  if (!source || notification?.targetId !== source.parentId ||
      !isValidOpaqueUid(actorId) || !isValidOpaqueUid(recipientId) ||
      actorId === recipientId) {
    return false;
  }
  const [mentions] = await readAll(
    reader,
    firestore.doc(`commentMentions/${commentMentionDocumentId(
      source.kind,
      source.parentId,
      source.commentId,
    )}`),
  );
  const record = exactCommentMentions(mentions, source);
  if (!record || record.actorId !== actorId ||
      !record.mentionUserIds.includes(recipientId)) {
    return false;
  }
  const authorId = await liveCommentParent(reader, firestore, {
    ...source,
    actorId,
    nowMs,
  });
  if (!authorId || authorId === recipientId) return false;
  const [commenterSees, mentionedSees] = [
    await audienceAllows(reader, firestore, {
      kind: source.kind, viewerId: actorId, authorId, nowMs,
    }),
    await audienceAllows(reader, firestore, {
      kind: source.kind, viewerId: recipientId, authorId, nowMs,
    }),
  ];
  return commenterSees && mentionedSees;
}

/**
 * serverEventReminder: the event is still scheduled at the same revision and
 * has not started, the recipient still opted in, and the recipient can still
 * read the event's channel (membership, bans, restricted-channel grants).
 */
async function serverEventReminderSourceIsCurrent({
  recipientId,
  notification,
  reader,
  firestore,
  nowMs = Date.now(),
}) {
  const source = parseServerEventPath(notification?.sourcePath);
  const revision = Number(notification?.sourceGeneration);
  if (!source || notification?.targetId !== source.serverId ||
      notification?.targetSubId !== source.channelId ||
      !isValidOpaqueUid(recipientId) || !Number.isSafeInteger(revision) ||
      revision < 1) {
    return false;
  }
  const eventPath = notification.sourcePath;
  const [event, response] = await readAll(
    reader,
    firestore.doc(eventPath),
    firestore.doc(`${eventPath}/responses/${recipientId}`),
  );
  const eventData = event.exists ? event.data() ?? {} : null;
  const responseData = response.exists ? response.data() ?? {} : null;
  const startsAtMs = timestampMillis(eventData?.startsAt);
  if (!eventData || eventData.schemaVersion !== 1 ||
      eventData.status !== "scheduled" || eventData.revision !== revision ||
      eventData.reminderOptInEnabled !== true ||
      eventData.serverId !== source.serverId ||
      eventData.channelId !== source.channelId ||
      eventData.eventId !== source.eventId ||
      eventData.authorId !== notification?.actorId ||
      startsAtMs === null || startsAtMs <= nowMs ||
      !responseData || responseData.userId !== recipientId ||
      responseData.reminderRequested !== true) {
    return false;
  }
  return channelReadable(reader, firestore, {
    uid: recipientId,
    serverId: source.serverId,
    channelId: source.channelId,
  });
}

async function channelReadable(reader, firestore, { uid, serverId, channelId }) {
  // readChannelAccess reads through `transaction.get`/`getAll`. A plain
  // Firestore instance has only `getAll`, so give it the one-method shim.
  const transaction = reader !== firestore
    ? reader
    : {
      getAll: (...references) => firestore.getAll(...references),
      get: async (reference) => (await firestore.getAll(reference))[0],
    };
  try {
    await readChannelAccess({
      db: firestore,
      transaction,
      uid,
      serverId,
      channelId,
      capability: "read",
    });
    return true;
  } catch (error) {
    // Every refusal from the Server authority is an HttpsError ("denied",
    // reconciliation, malformed id). Anything else is infrastructure and
    // must stay retryable.
    if (error instanceof HttpsError) return false;
    throw error;
  }
}

/**
 * serverRole: the recipient's membership is still the exact authorization
 * revision the promotion produced, the role still outranks plain `member`,
 * and the server root is still active.
 */
async function serverRoleSourceIsCurrent({
  recipientId,
  notification,
  reader,
  firestore,
}) {
  const serverId = notification?.targetId;
  const revision = Number(notification?.sourceGeneration);
  if (typeof serverId !== "string" || !SAFE_SEGMENT.test(serverId) ||
      !isValidOpaqueUid(recipientId) ||
      notification?.sourcePath !== `clubs/${serverId}/members/${recipientId}` ||
      !Number.isSafeInteger(revision) || revision < 1) {
    return false;
  }
  const [root, membership] = await readAll(
    reader,
    firestore.doc(`clubs/${serverId}`),
    firestore.doc(`clubs/${serverId}/members/${recipientId}`),
  );
  let member = null;
  const valid = refusal(() => {
    const server = canonicalServer(root, { allowHeld: true });
    member = canonicalMember(membership, recipientId, server);
  });
  return valid && member.authorizationRevision === revision &&
    (ROLE_POWER[member.role] ?? 0) > (ROLE_POWER.member ?? 0);
}

async function engagementNotificationSourceIsCurrent(args) {
  switch (args.notification?.type) {
    case "momentComment":
    case "reelComment":
      return commentNotificationSourceIsCurrent(args);
    case "commentMention":
      return commentMentionSourceIsCurrent(args);
    case "serverEventReminder":
      return serverEventReminderSourceIsCurrent(args);
    case "serverRole":
      return serverRoleSourceIsCurrent(args);
    default:
      return false;
  }
}

module.exports = {
  ENGAGEMENT_NOTIFICATION_TYPES,
  audienceAllows,
  channelReadable,
  commentMentionSourceIsCurrent,
  commentNotificationSourceIsCurrent,
  commentSourcePath,
  engagementNotificationSourceIsCurrent,
  liveCommentParent,
  parseCommentSourcePath,
  parseServerEventPath,
  serverEventReminderSourceIsCurrent,
  serverRoleSourceIsCurrent,
  voiceMomentAudienceAllows,
};
