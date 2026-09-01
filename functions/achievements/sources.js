const { isValidOpaqueUid } = require("./identity");

const SAFE_SEGMENT = /^[A-Za-z0-9_-]{1,128}$/u;
const CLUB_WRITER_ROLES = new Set([
  "owner",
  "coOwner",
  "admin",
  "moderator",
  "member",
]);
const CANONICAL_WRITE_CLOCK_SKEW_MS = 5 * 60 * 1000;
const DIRECT_MESSAGE_KEYS = Object.freeze([
  "content",
  "conversationId",
  "durationSeconds",
  "editedAt",
  "isDeleted",
  "mediaUrl",
  "reactions",
  "readBy",
  "replyToContent",
  "replyToMessageId",
  "replyToSenderId",
  "schemaVersion",
  "senderId",
  "sentAt",
  "sequence",
  "type",
]);
const CLUB_MESSAGE_KEYS = Object.freeze([
  "channelId",
  "clubId",
  "content",
  "editedAt",
  "isDeleted",
  "senderId",
  "senderName",
  "senderPhotoUrl",
  "sentAt",
]);
const ROOM_MESSAGE_KEYS = Object.freeze([
  "createdAt",
  "reactions",
  "senderId",
  "senderName",
  "senderPhotoUrl",
  "text",
]);
const MOMENT_KEYS = Object.freeze([
  "audioUrl",
  "authorId",
  "authorName",
  "authorPhotoUrl",
  "caption",
  "commentCount",
  "createdAt",
  "durationSeconds",
  "isDeleted",
  "isPublished",
  "likeCount",
  "mediaContentType",
  "mediaGeneration",
  "mediaSize",
  "publishedAt",
  "replyToMomentId",
  "schemaVersion",
  "status",
  "storagePath",
  "updatedAt",
]);

function safeSegment(value) {
  return typeof value === "string" && SAFE_SEGMENT.test(value) ? value : null;
}

function opaqueUid(value) {
  return isValidOpaqueUid(value) ? value : null;
}

function timestampDate(value) {
  const date =
    value instanceof Date
      ? value
      : typeof value?.toDate === "function"
        ? value.toDate()
        : null;
  return date instanceof Date && Number.isFinite(date.getTime()) ? date : null;
}

function isPlainObject(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function hasExactKeys(value, expected) {
  if (!isPlainObject(value)) return false;
  const keys = Object.keys(value).sort();
  return (
    keys.length === expected.length &&
    keys.every((key, index) => key === expected[index])
  );
}

function canonicalWriteTime(embeddedTimestamp, sourceCreatedAt) {
  const embedded = timestampDate(embeddedTimestamp);
  const source = timestampDate(sourceCreatedAt);
  if (
    !embedded ||
    !source ||
    Math.abs(embedded.getTime() - source.getTime()) >
      CANONICAL_WRITE_CLOCK_SKEW_MS
  ) {
    return null;
  }
  // Firestore snapshot createTime is server evidence and therefore wins over
  // any timestamp embedded in a document body.
  return source;
}

function validOptionalText(value, maximum) {
  return (
    value === null || (typeof value === "string" && value.length <= maximum)
  );
}

function safeStorageInteger(value) {
  if (Number.isSafeInteger(value)) return value;
  if (typeof value !== "string" || !/^[0-9]{1,16}$/u.test(value)) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

function nonEmptyText(value, maximum) {
  return (
    typeof value === "string" &&
    value.trim().length > 0 &&
    value.trim().length <= maximum
  );
}

function incrementEvent({
  sourceType,
  sourceKey,
  beneficiaryId,
  actorId,
  metric,
  occurredAt,
}) {
  return {
    sourceType,
    sourceKey,
    beneficiaryId,
    actorId,
    metric,
    mode: "increment",
    delta: 1,
    occurredAt: timestampDate(occurredAt),
  };
}

function adaptDirectMessageCreated({
  conversationId,
  messageId,
  message,
  conversation,
  sourceCreatedAt = null,
}) {
  const safeConversationId = safeSegment(conversationId);
  const safeMessageId = safeSegment(messageId);
  const senderId = opaqueUid(message?.senderId);
  const participants = conversation?.participantIds;
  const occurredAt = canonicalWriteTime(message?.sentAt, sourceCreatedAt);
  const replyMessageId = message?.replyToMessageId;
  const replySenderId = message?.replyToSenderId;
  if (
    !safeConversationId ||
    !safeMessageId ||
    !senderId ||
    !occurredAt ||
    !hasExactKeys(message, DIRECT_MESSAGE_KEYS) ||
    message.schemaVersion !== 2 ||
    message.conversationId !== safeConversationId ||
    !Number.isSafeInteger(message.sequence) ||
    message.sequence < 1 ||
    !Array.isArray(participants) ||
    participants.length !== 2 ||
    new Set(participants).size !== 2 ||
    !participants.every((id) => opaqueUid(id)) ||
    !participants.includes(senderId) ||
    conversation?.schemaVersion !== 2 ||
    message.type !== "text" ||
    message.isDeleted !== false ||
    message.editedAt !== null ||
    message.mediaUrl !== null ||
    message.durationSeconds !== null ||
    !nonEmptyText(message.content, 2000) ||
    message.content !== message.content.trim() ||
    !isPlainObject(message.reactions) ||
    Object.keys(message.reactions).length !== 0 ||
    !Array.isArray(message.readBy) ||
    message.readBy.length !== 1 ||
    message.readBy[0] !== senderId ||
    (replyMessageId !== null && !safeSegment(replyMessageId)) ||
    (replySenderId !== null &&
      (!opaqueUid(replySenderId) || !participants.includes(replySenderId))) ||
    !validOptionalText(message.replyToContent, 240) ||
    (replyMessageId === null) !== (replySenderId === null) ||
    (replyMessageId === null) !== (message.replyToContent === null)
  ) {
    return null;
  }
  return incrementEvent({
    sourceType: "dmMessageCreated",
    sourceKey: `conversations/${safeConversationId}/messages/${safeMessageId}`,
    beneficiaryId: senderId,
    actorId: senderId,
    metric: "messages",
    occurredAt,
  });
}

function adaptClubMessageCreated({
  clubId,
  channelId,
  messageId,
  message,
  club,
  channel,
  member,
  sourceCreatedAt = null,
}) {
  const ids = [clubId, channelId, messageId].map(safeSegment);
  const senderId = opaqueUid(message?.senderId);
  const occurredAt = canonicalWriteTime(message?.sentAt, sourceCreatedAt);
  if (
    ids.some((id) => !id) ||
    !senderId ||
    !occurredAt ||
    !hasExactKeys(message, CLUB_MESSAGE_KEYS) ||
    message?.clubId !== clubId ||
    message?.channelId !== channelId ||
    message?.isDeleted !== false ||
    message?.editedAt !== null ||
    !nonEmptyText(message?.content, 2000) ||
    message.content !== message.content.trim() ||
    !nonEmptyText(message?.senderName, 120) ||
    !validOptionalText(message?.senderPhotoUrl, 2048) ||
    club?.status !== "active" ||
    !["chat", "announcement"].includes(channel?.type) ||
    member?.userId !== senderId ||
    member?.banned === true ||
    !CLUB_WRITER_ROLES.has(member?.role)
  ) {
    return null;
  }
  return incrementEvent({
    sourceType: "clubMessageCreated",
    sourceKey: `clubs/${clubId}/channels/${channelId}/messages/${messageId}`,
    beneficiaryId: senderId,
    actorId: senderId,
    metric: "messages",
    occurredAt,
  });
}

function adaptRoomMessageCreated({
  roomId,
  messageId,
  message,
  room,
  senderAuthorized,
  sourceCreatedAt = null,
}) {
  const safeRoomId = safeSegment(roomId);
  const safeMessageId = safeSegment(messageId);
  const senderId = opaqueUid(message?.senderId);
  const occurredAt = canonicalWriteTime(message?.createdAt, sourceCreatedAt);
  if (
    !safeRoomId ||
    !safeMessageId ||
    !senderId ||
    senderAuthorized !== true ||
    !occurredAt ||
    !hasExactKeys(message, ROOM_MESSAGE_KEYS) ||
    room?.status !== "active" ||
    !nonEmptyText(message?.text, 500) ||
    message.text !== message.text.trim() ||
    !nonEmptyText(message?.senderName, 120) ||
    !validOptionalText(message?.senderPhotoUrl, 2048) ||
    !isPlainObject(message?.reactions) ||
    Object.keys(message.reactions).length !== 0
  ) {
    return null;
  }
  return incrementEvent({
    sourceType: "roomMessageCreated",
    sourceKey: `rooms/${safeRoomId}/messages/${safeMessageId}`,
    beneficiaryId: senderId,
    actorId: senderId,
    metric: "messages",
    occurredAt,
  });
}

function adaptRoomCreated({ roomId, room, sourceCreatedAt = null }) {
  const safeRoomId = safeSegment(roomId);
  const hostId = opaqueUid(room?.hostId);
  if (
    !safeRoomId ||
    !hostId ||
    room?.roomKind === "clubLounge" ||
    room?.clubId ||
    !["community", "temporary"].includes(room?.roomType)
  ) {
    return null;
  }
  return incrementEvent({
    sourceType: "roomCreated",
    sourceKey: `rooms/${safeRoomId}`,
    beneficiaryId: hostId,
    actorId: hostId,
    metric: "rooms",
    occurredAt: sourceCreatedAt,
  });
}

function adaptCommunityJoined({
  kind,
  communityId,
  userId,
  roomKind = null,
  sourceCreatedAt = null,
}) {
  const safeCommunityId = safeSegment(communityId);
  const safeUserId = opaqueUid(userId);
  if (
    !safeCommunityId ||
    !safeUserId ||
    !["club", "room"].includes(kind) ||
    (kind === "room" && roomKind === "clubLounge")
  ) {
    return null;
  }
  const sourceKey =
    kind === "club"
      ? `clubs/${safeCommunityId}/members/${safeUserId}`
      : `rooms/${safeCommunityId}/roomMembers/${safeUserId}`;
  return incrementEvent({
    sourceType: "communityJoined",
    sourceKey,
    beneficiaryId: safeUserId,
    actorId: safeUserId,
    metric: "communities",
    occurredAt: sourceCreatedAt,
  });
}

function adaptMomentPublished({
  momentId,
  before,
  after,
  storageObject,
  sourceUpdatedAt = null,
}) {
  const safeMomentId = safeSegment(momentId);
  const authorId = opaqueUid(after?.authorId);
  const mediaSize = safeStorageInteger(storageObject?.size);
  const mediaGeneration =
    typeof storageObject?.generation === "string"
      ? storageObject.generation
      : Number.isSafeInteger(storageObject?.generation)
        ? String(storageObject.generation)
        : null;
  const occurredAt = canonicalWriteTime(after?.updatedAt, sourceUpdatedAt);
  const customMetadata = storageObject?.metadata;
  const customMetadataKeys = isPlainObject(customMetadata)
    ? Object.keys(customMetadata)
    : [];
  const expectedStoragePath =
    authorId && safeMomentId
      ? `voice_moments/${authorId}/${safeMomentId}.m4a`
      : null;
  if (
    !safeMomentId ||
    !/^[a-f0-9]{20}$/u.test(safeMomentId) ||
    !authorId ||
    !occurredAt ||
    !hasExactKeys(before, MOMENT_KEYS) ||
    !hasExactKeys(after, MOMENT_KEYS) ||
    before.schemaVersion !== 2 ||
    after.schemaVersion !== 2 ||
    before?.isPublished !== false ||
    before?.status !== "uploading" ||
    before?.isDeleted !== false ||
    after?.isPublished !== true ||
    before?.authorId !== after?.authorId ||
    after?.status !== "published" ||
    after?.isDeleted !== false ||
    !Number.isSafeInteger(after?.durationSeconds) ||
    after.durationSeconds < 1 ||
    after.durationSeconds > 60 ||
    !nonEmptyText(after?.authorName, 120) ||
    !validOptionalText(after?.authorPhotoUrl, 2048) ||
    typeof after?.caption !== "string" ||
    after.caption.length > 280 ||
    !Number.isSafeInteger(after?.likeCount) ||
    after.likeCount < 0 ||
    !Number.isSafeInteger(after?.commentCount) ||
    after.commentCount < 0 ||
    after?.replyToMomentId !== null ||
    !timestampDate(after?.createdAt) ||
    !timestampDate(after?.publishedAt) ||
    after?.storagePath !== expectedStoragePath ||
    (after?.audioUrl !== null &&
      (typeof after.audioUrl !== "string" ||
        !after.audioUrl.startsWith("https://"))) ||
    storageObject?.name !== expectedStoragePath ||
    !["audio/mp4", "audio/m4a", "audio/x-m4a"].includes(
      storageObject?.contentType,
    ) ||
    mediaSize === null ||
    mediaSize < 512 ||
    mediaSize > 12 * 1024 * 1024 ||
    !mediaGeneration ||
    after?.mediaGeneration !== mediaGeneration ||
    after?.mediaSize !== mediaSize ||
    after?.mediaContentType !== storageObject?.contentType ||
    !isPlainObject(customMetadata) ||
    customMetadataKeys.some(
      (key) =>
        !["authorId", "firebaseStorageDownloadTokens", "momentId"].includes(
          key,
        ),
    ) ||
    customMetadata.authorId !== authorId ||
    customMetadata.momentId !== safeMomentId
  ) {
    return null;
  }
  return incrementEvent({
    sourceType: "momentPublished",
    sourceKey: `voiceMoments/${safeMomentId}`,
    beneficiaryId: authorId,
    actorId: authorId,
    metric: "moments",
    occurredAt,
  });
}

function adaptReactionReceived({
  kind,
  contentKey,
  reactorId,
  authorId,
  contentDeleted = false,
  sourceCreatedAt = null,
}) {
  const safeReactorId = opaqueUid(reactorId);
  const safeAuthorId = opaqueUid(authorId);
  if (
    !safeReactorId ||
    !safeAuthorId ||
    safeReactorId === safeAuthorId ||
    contentDeleted ||
    typeof contentKey !== "string" ||
    !contentKey.trim() ||
    contentKey.length > 700 ||
    !["directMessage", "roomMessage", "momentLike"].includes(kind)
  ) {
    return null;
  }
  return incrementEvent({
    sourceType: "reactionReceived",
    // Reactor is part of the permanent key: changing emoji or remove/re-add
    // cannot repeatedly reward the same content-author pair.
    sourceKey: `${kind}/${contentKey.trim()}/reactors/${safeReactorId}`,
    beneficiaryId: safeAuthorId,
    actorId: safeReactorId,
    metric: "reactions",
    occurredAt: sourceCreatedAt,
  });
}

function adaptSocialMetricSnapshot({
  uid,
  metric,
  value,
  version,
  actorId = null,
}) {
  const safeUid = opaqueUid(uid);
  const safeActorId = actorId === null ? null : opaqueUid(actorId);
  if (
    !safeUid ||
    (safeActorId === null && actorId !== null) ||
    !["friends", "followers"].includes(metric) ||
    !Number.isSafeInteger(value) ||
    value < 0 ||
    !Number.isSafeInteger(version) ||
    version < 0
  ) {
    return null;
  }
  return {
    sourceType: "socialMetricSnapshot",
    sourceKey: `users/${safeUid}/social/${metric}/versions/${version}`,
    beneficiaryId: safeUid,
    actorId: safeActorId,
    metric,
    mode: "absolute",
    value,
    version,
    occurredAt: null,
  };
}

function adaptActiveDay({ uid, occurredAt }) {
  const safeUid = opaqueUid(uid);
  const date = timestampDate(occurredAt);
  if (!safeUid || !date) return null;
  const utcDay = date.toISOString().slice(0, 10);
  return incrementEvent({
    sourceType: "activeDay",
    sourceKey: `users/${safeUid}/activeDays/${utcDay}`,
    beneficiaryId: safeUid,
    actorId: safeUid,
    metric: "activeDays",
    // The canonical identity of this event is the UTC day, so every field of
    // its canonical content must be a function of (uid, day) alone. Carrying
    // the triggering event's exact time here made the second qualifying
    // action of a user-day derive a different fingerprint for the same
    // eventId — an unresolvable ledger collision.
    occurredAt: new Date(`${utcDay}T00:00:00.000Z`),
  });
}

function eventsWithActorActiveDay(primaryEvent, occurredAt) {
  if (!primaryEvent) return [];
  const activeDay = primaryEvent.actorId
    ? adaptActiveDay({ uid: primaryEvent.actorId, occurredAt })
    : null;
  return activeDay ? [primaryEvent, activeDay] : [primaryEvent];
}

module.exports = {
  adaptActiveDay,
  adaptClubMessageCreated,
  adaptCommunityJoined,
  adaptDirectMessageCreated,
  adaptMomentPublished,
  adaptReactionReceived,
  adaptRoomCreated,
  adaptRoomMessageCreated,
  adaptSocialMetricSnapshot,
  eventsWithActorActiveDay,
};
