const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const { FieldValue } = require("firebase-admin/firestore");

const { isValidOpaqueUid } = require("./identity");
const {
  AchievementOutboxValidationError,
  getDefaultAchievementRuntime,
} = require("./runtime");
const {
  adaptClubMessageCreated,
  adaptCommunityJoined,
  adaptDirectMessageCreated,
  adaptMomentPublished,
  adaptReactionReceived,
  adaptRoomCreated,
  adaptRoomMessageCreated,
  adaptSocialMetricSnapshot,
} = require("./sources");

const REGION = "europe-west1";
const SAFE_SEGMENT = /^[A-Za-z0-9_-]{1,128}$/u;
const CLUB_MEMBER_ROLES = new Set([
  "owner",
  "coOwner",
  "admin",
  "moderator",
  "member",
  "guest",
]);
const DIRECT_REACTION_EVENT_KEYS = Object.freeze([
  "actorId",
  "conversationId",
  "createdAt",
  "emoji",
  "messageId",
  "recipientId",
  "schemaVersion",
  "sourceKey",
]);
const MOMENT_LIKE_KEYS = Object.freeze([
  "createdAt",
  "momentId",
  "schemaVersion",
  "userId",
]);

function safeSegment(value) {
  return typeof value === "string" && SAFE_SEGMENT.test(value) ? value : null;
}

function timestampDate(value) {
  const date = value instanceof Date
    ? value
    : typeof value?.toDate === "function"
      ? value.toDate()
      : null;
  return date instanceof Date && Number.isFinite(date.getTime())
    ? new Date(date.getTime())
    : null;
}

function dataOf(snapshot) {
  return snapshot && typeof snapshot.data === "function"
    ? snapshot.data() ?? null
    : null;
}

function sourceTime(snapshot, kind = "create") {
  const preferred = kind === "update" ? snapshot?.updateTime : snapshot?.createTime;
  return timestampDate(preferred) ?? timestampDate(snapshot?.updateTime);
}

function exactKeys(value, expected) {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      Object.getPrototypeOf(value) !== Object.prototype) return false;
  const keys = Object.keys(value).sort();
  return keys.length === expected.length &&
    keys.every((key, index) => key === expected[index]);
}

function storageObjectNotFound(error) {
  return error?.code === 404 || error?.code === "404" ||
    error?.code === "not-found" || error?.statusCode === 404;
}

function restrictionActive(restriction, occurredAt) {
  if (!restriction || restriction.type !== "communicationMute") return false;
  if (restriction.expiresAt === null || restriction.expiresAt === undefined) {
    return true;
  }
  const expiry = timestampDate(restriction.expiresAt);
  return !expiry || !occurredAt || expiry.getTime() > occurredAt.getTime();
}

function activeProfile(profile) {
  return profile && profile.banned !== true && profile.disabled !== true &&
    profile.deleted !== true && profile.status !== "deleted";
}

class FirestoreAchievementSourceReader {
  constructor({ db = null, bucket = null } = {}) {
    this.db = db;
    this.bucket = bucket;
  }

  database() {
    return this.db ?? require("../utils/firestore").db;
  }

  async read(path) {
    const snapshot = await this.database().doc(path).get();
    return snapshot.exists ? snapshot.data() ?? null : null;
  }

  async readStorageObject(path) {
    const bucket = this.bucket ?? require("firebase-admin/storage")
      .getStorage()
      .bucket();
    const [metadata] = await bucket.file(path).getMetadata();
    return {
      name: path,
      contentType: metadata.contentType,
      size: metadata.size,
      generation: metadata.generation,
      metadata: metadata.metadata ?? metadata.customMetadata ?? {},
    };
  }

  async markOutboxProcessed(reference, result) {
    await reference.set({
      status: "processed",
      outcome: result.outcome,
      processedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }

  async markOutboxInvalid(reference) {
    await reference.set({
      status: "invalid",
      failureCode: "invalid-canonical-achievement-event",
      processedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
}

async function authorityFor(reader, uid, occurredAt) {
  if (!isValidOpaqueUid(uid)) return false;
  const [profile, restriction] = await Promise.all([
    reader.read(`users/${uid}`),
    reader.read(`restrictions/${uid}`),
  ]);
  return activeProfile(profile) && !restrictionActive(restriction, occurredAt);
}

function createAchievementSourceHandlers({
  reader = new FirestoreAchievementSourceReader(),
  runtimeProvider = getDefaultAchievementRuntime,
} = {}) {
  const runtime = () => runtimeProvider();
  const invalid = (reason) => ({ outcome: `skipped:${reason}`, results: [] });

  async function onDirectMessageCreated(event) {
    const snapshot = event?.data;
    const message = dataOf(snapshot);
    const conversationId = safeSegment(event?.params?.conversationId);
    const messageId = safeSegment(event?.params?.messageId);
    const occurredAt = sourceTime(snapshot);
    const senderId = message?.senderId;
    if (!conversationId || !messageId || !occurredAt ||
        !isValidOpaqueUid(senderId)) return invalid("invalid-direct-message");
    const [conversation, authorized] = await Promise.all([
      reader.read(`conversations/${conversationId}`),
      authorityFor(reader, senderId, occurredAt),
    ]);
    if (!authorized) return invalid("unauthorized-direct-sender");
    const source = adaptDirectMessageCreated({
      conversationId,
      messageId,
      message,
      conversation,
      sourceCreatedAt: occurredAt,
    });
    return runtime().processSourceEvent(source);
  }

  async function onClubMessageCreated(event) {
    const snapshot = event?.data;
    const message = dataOf(snapshot);
    const clubId = safeSegment(event?.params?.clubId);
    const channelId = safeSegment(event?.params?.channelId);
    const messageId = safeSegment(event?.params?.messageId);
    const occurredAt = sourceTime(snapshot);
    const senderId = message?.senderId;
    if (!clubId || !channelId || !messageId || !occurredAt ||
        !isValidOpaqueUid(senderId)) return invalid("invalid-club-message");
    const [club, channel, member, authorized] = await Promise.all([
      reader.read(`clubs/${clubId}`),
      reader.read(`clubs/${clubId}/channels/${channelId}`),
      reader.read(`clubs/${clubId}/members/${senderId}`),
      authorityFor(reader, senderId, occurredAt),
    ]);
    if (!authorized) return invalid("unauthorized-club-sender");
    const source = adaptClubMessageCreated({
      clubId,
      channelId,
      messageId,
      message,
      club,
      channel,
      member,
      sourceCreatedAt: occurredAt,
    });
    return runtime().processSourceEvent(source);
  }

  async function onRoomMessageCreated(event) {
    const snapshot = event?.data;
    const message = dataOf(snapshot);
    const roomId = safeSegment(event?.params?.roomId);
    const messageId = safeSegment(event?.params?.messageId);
    const occurredAt = sourceTime(snapshot);
    const senderId = message?.senderId;
    if (!roomId || !messageId || !occurredAt ||
        !isValidOpaqueUid(senderId)) return invalid("invalid-room-message");
    const [room, participant, member, authorizedAccount] = await Promise.all([
      reader.read(`rooms/${roomId}`),
      reader.read(`rooms/${roomId}/participants/${senderId}`),
      reader.read(`rooms/${roomId}/roomMembers/${senderId}`),
      authorityFor(reader, senderId, occurredAt),
    ]);
    const senderAuthorized = authorizedAccount && (
      room?.hostId === senderId || participant?.userId === senderId ||
      member?.userId === senderId
    );
    const source = adaptRoomMessageCreated({
      roomId,
      messageId,
      message,
      room,
      senderAuthorized,
      sourceCreatedAt: occurredAt,
    });
    return runtime().processSourceEvent(source);
  }

  async function onRoomCreated(event) {
    const snapshot = event?.data;
    const room = dataOf(snapshot);
    const roomId = safeSegment(event?.params?.roomId);
    const occurredAt = sourceTime(snapshot);
    const hostId = room?.hostId;
    if (!roomId || !occurredAt || !isValidOpaqueUid(hostId) ||
        !await authorityFor(reader, hostId, occurredAt)) {
      return invalid("invalid-room-root");
    }
    return runtime().processSourceEvent(adaptRoomCreated({
      roomId,
      room,
      sourceCreatedAt: occurredAt,
    }));
  }

  async function onClubMemberCreated(event) {
    const snapshot = event?.data;
    const member = dataOf(snapshot);
    const clubId = safeSegment(event?.params?.clubId);
    const memberId = event?.params?.memberId;
    const occurredAt = sourceTime(snapshot);
    if (!clubId || !occurredAt || !isValidOpaqueUid(memberId) ||
        member?.userId !== memberId || member?.banned === true ||
        !CLUB_MEMBER_ROLES.has(member?.role)) {
      return invalid("invalid-club-membership");
    }
    const [club, authorized] = await Promise.all([
      reader.read(`clubs/${clubId}`),
      authorityFor(reader, memberId, occurredAt),
    ]);
    if (club?.status !== "active" || !authorized) {
      return invalid("inactive-club-membership");
    }
    return runtime().processSourceEvent(adaptCommunityJoined({
      kind: "club",
      communityId: clubId,
      userId: memberId,
      sourceCreatedAt: occurredAt,
    }));
  }

  async function onRoomMemberCreated(event) {
    const snapshot = event?.data;
    const member = dataOf(snapshot);
    const roomId = safeSegment(event?.params?.roomId);
    const memberId = event?.params?.memberId;
    const occurredAt = sourceTime(snapshot);
    if (!roomId || !occurredAt || !isValidOpaqueUid(memberId) ||
        member?.userId !== memberId) return invalid("invalid-room-membership");
    const [room, authorized] = await Promise.all([
      reader.read(`rooms/${roomId}`),
      authorityFor(reader, memberId, occurredAt),
    ]);
    if (room?.status !== "active" || room?.roomType !== "community" ||
        !authorized) return invalid("inactive-room-membership");
    return runtime().processSourceEvent(adaptCommunityJoined({
      kind: "room",
      communityId: roomId,
      userId: memberId,
      roomKind: room.roomKind ?? (room.clubId ? "clubLounge" : null),
      sourceCreatedAt: occurredAt,
    }));
  }

  async function onMomentPublished(event) {
    const beforeSnapshot = event?.data?.before;
    const afterSnapshot = event?.data?.after;
    const before = dataOf(beforeSnapshot);
    const after = dataOf(afterSnapshot);
    const momentId = safeSegment(event?.params?.momentId);
    const occurredAt = sourceTime(afterSnapshot, "update");
    const authorId = after?.authorId;
    if (!momentId || !occurredAt || !isValidOpaqueUid(authorId) ||
        !await authorityFor(reader, authorId, occurredAt) ||
        typeof after?.storagePath !== "string") {
      return invalid("invalid-moment-publication");
    }
    let storageObject;
    try {
      storageObject = await reader.readStorageObject(after.storagePath);
    } catch (error) {
      if (storageObjectNotFound(error)) return invalid("missing-moment-media");
      throw error;
    }
    return runtime().processSourceEvent(adaptMomentPublished({
      momentId,
      before,
      after,
      storageObject,
      sourceUpdatedAt: occurredAt,
    }));
  }

  async function onDirectReactionCreated(event) {
    const snapshot = event?.data;
    const reaction = dataOf(snapshot);
    const occurredAt = sourceTime(snapshot);
    if (!exactKeys(reaction, DIRECT_REACTION_EVENT_KEYS) ||
        reaction.schemaVersion !== 1 || !occurredAt ||
        !isValidOpaqueUid(reaction.actorId) ||
        !isValidOpaqueUid(reaction.recipientId) ||
        !safeSegment(reaction.conversationId) ||
        !safeSegment(reaction.messageId) ||
        typeof reaction.emoji !== "string" || !reaction.emoji ||
        reaction.emoji.length > 16 ||
        reaction.sourceKey !== `conversations/${reaction.conversationId}` +
          `/messages/${reaction.messageId}`) {
      return invalid("invalid-direct-reaction-event");
    }
    const [message, conversation, actorAllowed, authorAllowed] = await Promise.all([
      reader.read(reaction.sourceKey),
      reader.read(`conversations/${reaction.conversationId}`),
      authorityFor(reader, reaction.actorId, occurredAt),
      authorityFor(reader, reaction.recipientId, occurredAt),
    ]);
    const authorId = message?.senderId;
    if (!actorAllowed || !authorAllowed || message?.schemaVersion !== 2 ||
        message?.conversationId !== reaction.conversationId ||
        message?.isDeleted !== false || authorId !== reaction.recipientId ||
        !Array.isArray(conversation?.participantIds) ||
        !conversation.participantIds.includes(reaction.actorId) ||
        !conversation.participantIds.includes(authorId)) {
      return invalid("unbound-direct-reaction-event");
    }
    return runtime().processSourceEvent(adaptReactionReceived({
      kind: "directMessage",
      contentKey: reaction.sourceKey,
      reactorId: reaction.actorId,
      authorId,
      sourceCreatedAt: occurredAt,
    }));
  }

  async function onMomentLikeCreated(event) {
    const snapshot = event?.data;
    const like = dataOf(snapshot);
    const momentId = safeSegment(event?.params?.momentId);
    const reactorId = event?.params?.reactorId;
    const occurredAt = sourceTime(snapshot);
    if (!momentId || !isValidOpaqueUid(reactorId) || !occurredAt ||
        !exactKeys(like, MOMENT_LIKE_KEYS) || like.schemaVersion !== 1 ||
        like.userId !== reactorId || like.momentId !== momentId) {
      return invalid("invalid-moment-like");
    }
    const moment = await reader.read(`voiceMoments/${momentId}`);
    const authorId = moment?.authorId;
    if (moment?.schemaVersion !== 2 || moment?.status !== "published" ||
        moment?.isPublished !== true || moment?.isDeleted !== false ||
        !isValidOpaqueUid(authorId)) return invalid("invalid-liked-moment");
    const [actorAllowed, authorAllowed] = await Promise.all([
      authorityFor(reader, reactorId, occurredAt),
      authorityFor(reader, authorId, occurredAt),
    ]);
    if (!actorAllowed || !authorAllowed) return invalid("unauthorized-moment-like");
    return runtime().processSourceEvent(adaptReactionReceived({
      kind: "momentLike",
      contentKey: `voiceMoments/${momentId}`,
      reactorId,
      authorId,
      sourceCreatedAt: occurredAt,
    }));
  }

  async function onUserSocialCountersChanged(event) {
    const before = dataOf(event?.data?.before) ?? {};
    const after = dataOf(event?.data?.after);
    const uid = event?.params?.userId;
    const occurredAt = sourceTime(event?.data?.after, "update");
    if (!after || !isValidOpaqueUid(uid) || !occurredAt ||
        !activeProfile(after)) return invalid("invalid-social-projection");
    const events = [];
    for (const config of [
      { metric: "friends", value: "friendCount", version: "friendAchievementRevision" },
      { metric: "followers", value: "followerCount", version: "followerAchievementRevision" },
    ]) {
      const previousVersion = before[config.version] ?? -1;
      const version = after[config.version];
      if (version === previousVersion) continue;
      if (!Number.isSafeInteger(previousVersion) || previousVersion < -1 ||
          !Number.isSafeInteger(version) || version <= previousVersion ||
          !Number.isSafeInteger(after[config.value]) || after[config.value] < 0) {
        return invalid("invalid-social-revision");
      }
      events.push(adaptSocialMetricSnapshot({
        uid,
        metric: config.metric,
        value: after[config.value],
        version,
      }));
    }
    if (events.length === 0) return invalid("unchanged-social-revision");
    const results = [];
    for (const source of events) {
      results.push(await runtime().processSourceEvent(source, {
        includeActiveDay: false,
      }));
    }
    return { outcome: "processed", results };
  }

  async function onOutboxCreated(event) {
    const snapshot = event?.data;
    const record = dataOf(snapshot);
    const outboxId = event?.params?.outboxId;
    if (!snapshot?.ref || typeof reader.markOutboxProcessed !== "function") {
      throw new Error("An outbox reference and marker are required.");
    }
    try {
      const result = await runtime().processOutboxRecord(record, outboxId);
      await reader.markOutboxProcessed(snapshot.ref, result);
      return result;
    } catch (error) {
      if (error instanceof AchievementOutboxValidationError &&
          typeof reader.markOutboxInvalid === "function") {
        await reader.markOutboxInvalid(snapshot.ref);
        return { outcome: "invalid", outboxId };
      }
      throw error;
    }
  }

  return Object.freeze({
    onClubMemberCreated,
    onClubMessageCreated,
    onDirectMessageCreated,
    onDirectReactionCreated,
    onMomentLikeCreated,
    onMomentPublished,
    onOutboxCreated,
    onRoomCreated,
    onRoomMemberCreated,
    onRoomMessageCreated,
    onUserSocialCountersChanged,
  });
}

const defaultHandlers = createAchievementSourceHandlers();

const onAchievementDirectMessageCreated = onDocumentCreated({
  document: "conversations/{conversationId}/messages/{messageId}",
  region: REGION,
  retry: true,
}, defaultHandlers.onDirectMessageCreated);

const onAchievementClubMessageCreated = onDocumentCreated({
  document: "clubs/{clubId}/channels/{channelId}/messages/{messageId}",
  region: REGION,
  retry: true,
}, defaultHandlers.onClubMessageCreated);

const onAchievementRoomMessageCreated = onDocumentCreated({
  document: "rooms/{roomId}/messages/{messageId}",
  region: REGION,
  retry: true,
}, defaultHandlers.onRoomMessageCreated);

const onAchievementRoomCreated = onDocumentCreated({
  document: "rooms/{roomId}",
  region: REGION,
  retry: true,
}, defaultHandlers.onRoomCreated);

const onAchievementClubMemberCreated = onDocumentCreated({
  document: "clubs/{clubId}/members/{memberId}",
  region: REGION,
  retry: true,
}, defaultHandlers.onClubMemberCreated);

const onAchievementRoomMemberCreated = onDocumentCreated({
  document: "rooms/{roomId}/roomMembers/{memberId}",
  region: REGION,
  retry: true,
}, defaultHandlers.onRoomMemberCreated);

const onAchievementMomentPublished = onDocumentUpdated({
  document: "voiceMoments/{momentId}",
  region: REGION,
  retry: true,
}, defaultHandlers.onMomentPublished);

const onAchievementDirectReactionCreated = onDocumentCreated({
  document: "directReactionEvents/{reactionEventId}",
  region: REGION,
  retry: true,
}, defaultHandlers.onDirectReactionCreated);

const onAchievementMomentLikeCreated = onDocumentCreated({
  document: "voiceMoments/{momentId}/likes/{reactorId}",
  region: REGION,
  retry: true,
}, defaultHandlers.onMomentLikeCreated);

const onAchievementUserSocialCountersChanged = onDocumentUpdated({
  document: "users/{userId}",
  region: REGION,
  retry: true,
}, defaultHandlers.onUserSocialCountersChanged);

const onAchievementOutboxCreated = onDocumentCreated({
  document: "achievementOutbox/{outboxId}",
  region: REGION,
  retry: true,
}, defaultHandlers.onOutboxCreated);

module.exports = {
  DIRECT_REACTION_EVENT_KEYS,
  FirestoreAchievementSourceReader,
  MOMENT_LIKE_KEYS,
  REGION,
  createAchievementSourceHandlers,
  storageObjectNotFound,
  onAchievementClubMemberCreated,
  onAchievementClubMessageCreated,
  onAchievementDirectMessageCreated,
  onAchievementDirectReactionCreated,
  onAchievementMomentLikeCreated,
  onAchievementMomentPublished,
  onAchievementOutboxCreated,
  onAchievementRoomCreated,
  onAchievementRoomMemberCreated,
  onAchievementRoomMessageCreated,
  onAchievementUserSocialCountersChanged,
};
