const { randomUUID } = require("node:crypto");
const { FieldPath } = require("firebase-admin/firestore");
const {
  fail, requireId, requireSafeInteger, requireUid, transactionGetAll,
} = require("../integrity/guards");
const {
  canonicalChannel, validRevision,
} = require("./authority");
const { serverChannelRefId, serverInviteRefPath } = require("./contract");
const {
  canonicalCompanyFile,
  canonicalCompanyFileDeletionJob,
  canonicalCompanyFileReservation,
  deletionJobId: companyFileDeletionJobId,
} = require("./company_files");
const {
  canonicalEpisode,
  canonicalJob: canonicalPodcastEgressJob,
  canonicalRecordingState,
} = require("./podcast_episodes");
const { mirrorIsVersionedForAnchor } = require("./rtc_binding");
const { assertSessionBinding } = require("./session_contract");
const {
  DELETION_JOBS: SERVER_MESSAGE_MEDIA_DELETION_JOBS,
  prefixDeletionJob: serverMessageMediaPrefixJob,
} = require("./message_media_contract");

const CONTENT_CLEANUP_VERSION = 1;
const CHANNEL_PHASES = Object.freeze([
  "grants", "messages", "events", "questions", "listItems",
  "whiteboardStrokes", "whiteboardState", "podcastEpisodes",
  "podcastRecordingState", "companyFiles", "sessions",
  "roomParticipants", "roomMessages", "roomMembers", "room", "final",
]);
const ROOM_PHASES = Object.freeze(["participants", "messages", "roomMembers", "final"]);
const SERVER_PHASES = Object.freeze([
  "channels", "orphanRooms", "invites", "members", "memberAuthorizations",
  "channelCategories", "moments", "familyMemoryReservations",
  "familyMemoryDeletionJobs", "familyMemoryStorage", "checkIns", "followers",
  "followMirrors", "bans", "final",
]);
const LOCAL_SERVER_COLLECTIONS = Object.freeze([
  "memberAuthorizations", "channelCategories", "moments", "checkIns", "bans",
]);
const FAMILY_MEMORY_PREFIX = "family_moments";
const FAMILY_MEMORY_LEASE_MS = 120_000;
const COMPANY_FILE_LEASE_MS = 120_000;
const PODCAST_EPISODE_LEASE_MS = 120_000;
const GENERATION_PATTERN = /^[0-9]{1,30}$/u;
const WHITEBOARD_COLORS = Object.freeze([
  "ink", "red", "orange", "green", "blue", "purple", "white",
]);
const MAX_WHITEBOARD_STROKES = 180;
const MAX_WHITEBOARD_POINTS = 64;

function reconciliation() {
  fail("failed-precondition", "The server content cleanup needs reconciliation.");
}

function deletionCleanupState(kind, { deletionRevision, ownerId, roomId = null }) {
  if (!validRevision(deletionRevision)) throw new TypeError("deletionRevision is required.");
  requireUid(ownerId, "ownerId");
  if (kind === "channelDelete") {
    if (roomId !== null) requireId(roomId, "roomId");
    return {
      contentCleanupVersion: CONTENT_CLEANUP_VERSION,
      contentCleanupPhase: CHANNEL_PHASES[0],
      contentCleanupStep: 0,
      deletionRevision,
      ownerId,
    };
  }
  if (kind !== "serverDelete") throw new TypeError("Unsupported deletion cleanup kind.");
  return {
    contentCleanupVersion: CONTENT_CLEANUP_VERSION,
    contentCleanupPhase: SERVER_PHASES[0],
    contentCleanupStep: 0,
    contentCleanupChannelId: null,
    contentCleanupChannelPhase: null,
    contentCleanupRoomId: null,
    contentCleanupRoomPhase: null,
    deletionRevision,
    ownerId,
  };
}

function validateContentCleanupShape(job) {
  if (!job || !["channelDelete", "serverDelete"].includes(job.kind) ||
      job.contentCleanupPending !== true ||
      job.contentCleanupVersion !== CONTENT_CLEANUP_VERSION ||
      !Number.isSafeInteger(job.contentCleanupStep) || job.contentCleanupStep < 0 ||
      job.contentCleanupStep >= Number.MAX_SAFE_INTEGER - 1 ||
      !validRevision(job.deletionRevision)) reconciliation();
  requireUid(job.ownerId, "ownerId");
  requireUid(job.requestedBy, "requestedBy");
  if (job.kind === "channelDelete") {
    requireId(job.channelId, "channelId");
    if (job.roomId !== null) requireId(job.roomId, "roomId");
    if (!CHANNEL_PHASES.includes(job.contentCleanupPhase) ||
        job.contentCleanupChannelId !== undefined || job.contentCleanupChannelPhase !== undefined ||
        job.contentCleanupRoomId !== undefined || job.contentCleanupRoomPhase !== undefined) reconciliation();
  } else {
    if (!SERVER_PHASES.includes(job.contentCleanupPhase) ||
        (job.contentCleanupChannelId !== null && typeof job.contentCleanupChannelId !== "string") ||
        (job.contentCleanupChannelPhase !== null && !CHANNEL_PHASES.includes(job.contentCleanupChannelPhase)) ||
        (job.contentCleanupRoomId !== null && typeof job.contentCleanupRoomId !== "string") ||
        (job.contentCleanupRoomPhase !== null && !ROOM_PHASES.includes(job.contentCleanupRoomPhase)) ||
        ((job.contentCleanupChannelId === null) !== (job.contentCleanupChannelPhase === null)) ||
        ((job.contentCleanupRoomId === null) !== (job.contentCleanupRoomPhase === null)) ||
        (job.contentCleanupPhase !== "channels" && job.contentCleanupChannelId !== null) ||
        (job.contentCleanupPhase !== "orphanRooms" && job.contentCleanupRoomId !== null)) reconciliation();
    if (job.contentCleanupChannelId !== null) requireId(job.contentCleanupChannelId, "cleanup channelId");
    if (job.contentCleanupRoomId !== null) requireId(job.contentCleanupRoomId, "cleanup roomId");
  }
  return job;
}

function cleanupResult({ complete = false, processed = 0 } = {}) {
  return {
    propagationComplete: true,
    rtcCleanupPending: false,
    cleanupPending: !complete,
    contentCleanupPending: !complete,
    recoveryRequired: false,
    processed,
  };
}

function canonicalDeletingRoot(snapshot, job) {
  const root = snapshot.exists ? snapshot.data() : null;
  if (!root || root.serverSchemaVersion !== 1 || root.ownerId !== job.ownerId ||
      root.deletionInProgress !== true || root.deletionOperationId !== job.operationId ||
      root.revision !== job.deletionRevision) reconciliation();
  return root;
}

function canonicalCleanupChannel(snapshot, job, { serverDeleting }) {
  let channel;
  try {
    channel = canonicalChannel(snapshot, job.serverId, { allowArchived: true, allowDeleting: true });
  } catch {
    reconciliation();
  }
  if (!serverDeleting && (channel.status !== "deleting" ||
      channel.deletionOperationId !== job.operationId || channel.revision !== job.deletionRevision)) {
    reconciliation();
  }
  return channel;
}

function canonicalCleanupRoom(snapshot, { serverId, channelId, roomId }) {
  if (!snapshot.exists) return null;
  const room = snapshot.data();
  if (room.serverSchemaVersion !== 1 || room.serverId !== serverId || room.clubId !== serverId ||
      room.channelId !== channelId || room.roomKind !== "serverChannel" || snapshot.id !== roomId) {
    reconciliation();
  }
  return room;
}

function checkpoint({ transaction, reference, job, Timestamp, clock, patch = {}, processed = 0 }) {
  const now = Timestamp.fromMillis(clock());
  transaction.update(reference, {
    ...patch,
    contentCleanupStep: job.contentCleanupStep + 1,
    updatedAt: now,
  });
  return cleanupResult({ processed });
}

function complete({ transaction, reference, job, Timestamp, clock, processed = 0 }) {
  const now = Timestamp.fromMillis(clock());
  transaction.update(reference, {
    status: "completed",
    contentCleanupPending: false,
    contentCleanupPhase: "final",
    contentCleanupStep: job.contentCleanupStep + 1,
    bridgeLeaseId: null,
    bridgeLeaseExpiresAtMillis: 0,
    retryAfterMillis: 0,
    lastErrorCode: null,
    completedAt: now,
    updatedAt: now,
  });
  return cleanupResult({ complete: true, processed });
}

/**
 * Channel photo/video bytes live under
 * server_message_media/{serverId}/{channelId}/{ownerUid}/. Their Storage
 * sweep is a durable, generation-guarded prefix job drained by
 * processServerChannelMessageMediaDeletionJobs (message_media.js), written in
 * the SAME transaction that finishes the message documents (channel) or the
 * channel walk (server, a catch-all over the whole server prefix). The
 * reviewed CHANNEL_PHASES / SERVER_PHASES sequences are unchanged and no
 * Storage adapter is needed inside this Firestore-only page. `set` keeps a
 * retried transaction idempotent.
 */
function enqueueServerMessageMediaSweep(db, transaction, { serverId, channelId = null, reason, now }) {
  const job = serverMessageMediaPrefixJob({ serverId, channelId, reason, now });
  transaction.set(db.doc(`${SERVER_MESSAGE_MEDIA_DELETION_JOBS}/${job.jobId}`), job.document);
}

function nextPhase(phases, phase) {
  const index = phases.indexOf(phase);
  if (index < 0 || index === phases.length - 1) reconciliation();
  return phases[index + 1];
}

async function firstPage(transaction, collection, FieldPathClass, pageSize) {
  return transaction.get(collection.orderBy(FieldPathClass.documentId()).limit(pageSize));
}

async function emptyProbe(transaction, collection, FieldPathClass) {
  return transaction.get(collection.orderBy(FieldPathClass.documentId()).limit(1));
}

function validParticipant(data, { serverId, channelId, roomId, uid }) {
  return data?.serverSchemaVersion === 1 && data.serverId === serverId &&
    data.channelId === channelId && data.roomId === roomId && data.userId === uid;
}

function validWhiteboardPoint(point) {
  return point && typeof point === "object" && !Array.isArray(point) &&
    Object.keys(point).sort().join(",") === "x,y" &&
    typeof point.x === "number" && Number.isFinite(point.x) &&
    typeof point.y === "number" && Number.isFinite(point.y) &&
    point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1;
}

function validateWhiteboardStroke(document, { serverId, channelId }) {
  const value = document.data();
  if (!value || value.schemaVersion !== 1 || value.serverId !== serverId ||
      value.channelId !== channelId || value.strokeId !== document.id ||
      value.strokeKind !== "polyline" || typeof value.authorId !== "string" ||
      value.authorId.length < 1 || value.authorId.length > 128 ||
      value.authorId.includes("/") ||
      !validRevision(value.generation) || !validRevision(value.sequence) ||
      value.revision !== 1 || !WHITEBOARD_COLORS.includes(value.color) ||
      !Number.isSafeInteger(value.lineWidth) || value.lineWidth < 1 ||
      value.lineWidth > 16 || !Array.isArray(value.points) ||
      value.points.length < 2 || value.points.length > MAX_WHITEBOARD_POINTS ||
      !value.points.every(validWhiteboardPoint) ||
      typeof value.createdAt?.toMillis !== "function") reconciliation();
}

function validateWhiteboardState(document, { serverId, channelId }) {
  const value = document.data();
  if (!value) reconciliation();
  const clearedPair = value.clearedAt === null
    ? value.clearedById === null
    : typeof value.clearedAt?.toMillis === "function" &&
      typeof value.clearedById === "string" &&
      value.clearedById.length >= 1 && value.clearedById.length <= 128 &&
      !value.clearedById.includes("/");
  if (document.id !== "main" || value.schemaVersion !== 1 ||
      value.serverId !== serverId || value.channelId !== channelId ||
      value.stateId !== "main" || !validRevision(value.generation) ||
      !validRevision(value.revision) || !Number.isSafeInteger(value.strokeCount) ||
      value.strokeCount < 0 || value.strokeCount > MAX_WHITEBOARD_STROKES ||
      !validRevision(value.nextSequence) ||
      typeof value.updatedAt?.toMillis !== "function" || !clearedPair) {
    reconciliation();
  }
}

function canonicalFamilyMemoryPath(path, serverId) {
  const prefix = `${FAMILY_MEMORY_PREFIX}/${serverId}/`;
  if (typeof path !== "string" || !path.startsWith(prefix)) reconciliation();
  const segments = path.split("/");
  if (segments.length !== 4 || segments[0] !== FAMILY_MEMORY_PREFIX ||
      segments[1] !== serverId || !segments[3]) reconciliation();
  try {
    requireUid(segments[2], "Family Memory ownerId");
  } catch (_) {
    reconciliation();
  }
  return path;
}

function canonicalFamilyMemoryReservation(snapshot, serverId) {
  const value = snapshot.data() ?? {};
  try {
    requireUid(value.ownerId, "Family Memory ownerId");
    requireId(value.memoryId, "Family Memory memoryId");
  } catch (_) {
    reconciliation();
  }
  if (value.schemaVersion !== 1 || value.kind !== "serverFamilyMemory" ||
      value.serverId !== serverId || value.memoryId !== snapshot.id ||
      !["uploading", "expiring"].includes(value.status)) reconciliation();
  canonicalFamilyMemoryPath(value.photoStoragePath, serverId);
  canonicalFamilyMemoryPath(value.voiceStoragePath, serverId);
  return value;
}

function canonicalFamilyMemoryDeletionJob(snapshot, serverId) {
  const value = snapshot.data() ?? {};
  try {
    requireUid(value.authorId, "Family Memory authorId");
    requireId(value.memoryId, "Family Memory memoryId");
  } catch (_) {
    reconciliation();
  }
  if (value.schemaVersion !== 1 || value.kind !== "serverFamilyMemoryDelete" ||
      value.serverId !== serverId || value.jobId !== snapshot.id ||
      value.status !== "pending" || value.photo?.storagePath === undefined ||
      value.voice?.storagePath === undefined) reconciliation();
  canonicalFamilyMemoryPath(value.photo.storagePath, serverId);
  canonicalFamilyMemoryPath(value.voice.storagePath, serverId);
  return value;
}

function canonicalServerFollow(snapshot, serverId) {
  const value = snapshot.data() ?? {};
  const expectedKeys = [
    "createdAt", "following", "schemaVersion", "serverId", "updatedAt", "userId",
  ];
  const keys = Object.keys(value).sort();
  try {
    requireUid(value.userId, "server follower userId");
  } catch (_) {
    reconciliation();
  }
  if (keys.length !== expectedKeys.length ||
      keys.some((key, index) => key !== expectedKeys[index]) ||
      value.schemaVersion !== 1 || value.serverId !== serverId ||
      value.following !== true || typeof value.createdAt?.toMillis !== "function" ||
      typeof value.updatedAt?.toMillis !== "function") reconciliation();
  return value;
}

/**
 * One bounded cleanup page. The convergence worker calls this only after all
 * captured RTC generations are positively ended. Firestore pages recheck the
 * deletion fence in their destructive transaction. The isolated Family
 * Memory Storage page uses the same fence plus an expiring durable lease, then
 * rechecks both before advancing its checkpoint.
 */
function createServerContentCleanupService({
  db, Timestamp, FieldPath: FieldPathClass = FieldPath, clock = Date.now,
  familyMemoryStorage = null,
  companyFileStorage = null,
  podcastEpisodeStorage = null,
}) {
  if (!db?.runTransaction || !Timestamp?.fromMillis ||
      typeof FieldPathClass?.documentId !== "function" || typeof clock !== "function") {
    throw new TypeError("db, Timestamp, FieldPath and clock are required.");
  }

  async function deleteChannelPage({
    transaction, reference, job, root, channelReference, channel, phase, serverDeleting,
  }) {
    const roomId = channel.roomId;
    const advance = (processed = 0) => checkpoint({
      transaction, reference, job, Timestamp, clock,
      patch: serverDeleting
        ? { contentCleanupChannelPhase: nextPhase(CHANNEL_PHASES, phase) }
        : { contentCleanupPhase: nextPhase(CHANNEL_PHASES, phase) },
      processed,
    });

    if (phase === "grants") {
      const page = await firstPage(transaction, channelReference.collection("accessGrants"), FieldPathClass, job.pageSize);
      const mirrorReferences = page.docs.map((document) => {
        const uid = requireUid(document.id);
        const grant = document.data();
        if (grant.userId !== uid || grant.serverId !== job.serverId || grant.channelId !== channelReference.id) reconciliation();
        return db.doc(`users/${uid}/serverChannelRefs/${serverChannelRefId(job.serverId, channelReference.id)}`);
      });
      const mirrors = mirrorReferences.length
        ? await transactionGetAll(transaction, ...mirrorReferences) : [];
      page.docs.forEach((document, index) => {
        transaction.delete(document.ref);
        if (mirrors[index]?.exists) transaction.delete(mirrors[index].ref);
      });
      return page.empty ? advance() : checkpoint({ transaction, reference, job, Timestamp, clock,
        processed: page.size });
    }

    if (phase === "messages") {
      const page = await firstPage(transaction, channelReference.collection("messages"), FieldPathClass, job.pageSize);
      page.docs.forEach((document) => transaction.delete(document.ref));
      if (!page.empty) {
        return checkpoint({ transaction, reference, job, Timestamp, clock, processed: page.size });
      }
      enqueueServerMessageMediaSweep(db, transaction, {
        serverId: job.serverId,
        channelId: channelReference.id,
        reason: serverDeleting ? "serverDelete" : "channelDelete",
        now: Timestamp.fromMillis(clock()),
      });
      return advance();
    }

    if (phase === "events") {
      const events = await firstPage(transaction, channelReference.collection("events"), FieldPathClass, 1);
      if (events.empty) return advance();
      const event = events.docs[0];
      const value = event.data();
      if (value.schemaVersion !== 1 || value.serverId !== job.serverId ||
          value.channelId !== channelReference.id || value.eventId !== event.id) reconciliation();
      const responses = await firstPage(transaction, event.ref.collection("responses"), FieldPathClass, job.pageSize);
      if (!responses.empty) {
        responses.docs.forEach((document) => transaction.delete(document.ref));
        return checkpoint({ transaction, reference, job, Timestamp, clock, processed: responses.size });
      }
      transaction.delete(event.ref);
      return checkpoint({ transaction, reference, job, Timestamp, clock, processed: 1 });
    }

    if (phase === "questions") {
      const questions = await firstPage(
        transaction,
        channelReference.collection("questions"),
        FieldPathClass,
        1,
      );
      if (questions.empty) return advance();
      const question = questions.docs[0];
      const value = question.data();
      if (value.schemaVersion !== 1 || value.serverId !== job.serverId ||
          value.channelId !== channelReference.id || value.questionId !== question.id ||
          value.questionKind !== "podcastQuestion" ||
          !["queued", "onAir"].includes(value.status) ||
          !Number.isSafeInteger(value.voteCount) || value.voteCount < 0 ||
          !validRevision(value.revision)) reconciliation();
      const votes = await firstPage(
        transaction,
        question.ref.collection("votes"),
        FieldPathClass,
        job.pageSize,
      );
      if (!votes.empty) {
        votes.docs.forEach((document) => {
          const vote = document.data();
          if (vote.schemaVersion !== 1 || vote.serverId !== job.serverId ||
              vote.channelId !== channelReference.id || vote.questionId !== question.id ||
              vote.userId !== document.id || typeof vote.active !== "boolean" ||
              !validRevision(vote.questionRevision) ||
              typeof vote.operationId !== "string" || vote.operationId.length < 1) {
            reconciliation();
          }
        });
        votes.docs.forEach((document) => transaction.delete(document.ref));
        return checkpoint({
          transaction, reference, job, Timestamp, clock, processed: votes.size,
        });
      }
      transaction.delete(question.ref);
      return checkpoint({
        transaction, reference, job, Timestamp, clock, processed: 1,
      });
    }

    if (phase === "listItems") {
      const page = await firstPage(
        transaction,
        channelReference.collection("listItems"),
        FieldPathClass,
        job.pageSize,
      );
      page.docs.forEach((document) => {
        const item = document.data();
        if (item.schemaVersion !== 1 || item.serverId !== job.serverId ||
            item.channelId !== channelReference.id || item.itemId !== document.id) {
          reconciliation();
        }
      });
      page.docs.forEach((document) => transaction.delete(document.ref));
      return page.empty ? advance() : checkpoint({
        transaction, reference, job, Timestamp, clock, processed: page.size,
      });
    }

    if (phase === "whiteboardStrokes") {
      const page = await firstPage(
        transaction,
        channelReference.collection("whiteboardStrokes"),
        FieldPathClass,
        job.pageSize,
      );
      page.docs.forEach((document) => validateWhiteboardStroke(document, {
        serverId: job.serverId,
        channelId: channelReference.id,
      }));
      page.docs.forEach((document) => transaction.delete(document.ref));
      return page.empty ? advance() : checkpoint({
        transaction, reference, job, Timestamp, clock, processed: page.size,
      });
    }

    if (phase === "whiteboardState") {
      const page = await firstPage(
        transaction,
        channelReference.collection("whiteboardState"),
        FieldPathClass,
        1,
      );
      page.docs.forEach((document) => validateWhiteboardState(document, {
        serverId: job.serverId,
        channelId: channelReference.id,
      }));
      page.docs.forEach((document) => transaction.delete(document.ref));
      return page.empty ? advance() : checkpoint({
        transaction, reference, job, Timestamp, clock, processed: page.size,
      });
    }

    // Podcast episodes may own private GCS bytes and are therefore handled by
    // processPodcastEpisodeStoragePage outside this Firestore-only
    // transaction. Reaching this branch means the phase router was bypassed.
    if (phase === "podcastEpisodes") reconciliation();

    if (phase === "podcastRecordingState") {
      const stateReference = channelReference.collection("podcastRecordingState").doc("main");
      const stateSnapshot = await transaction.get(stateReference);
      if (!stateSnapshot.exists) return advance();
      const state = canonicalRecordingState(stateSnapshot, {
        serverId: job.serverId,
        studioChannelId: channelReference.id,
      });
      const episodeReference = db.doc(
        `clubs/${job.serverId}/channels/${state.channelId}/episodes/${state.episodeId}`,
      );
      const egressReference = db.doc(`serverPodcastEgressJobs/${state.episodeId}`);
      const [episodeSnapshot, egressSnapshot] = await transactionGetAll(
        transaction,
        episodeReference,
        egressReference,
      );
      // The episode phase owns both the descriptor and its state projection.
      // A leftover state is safe to retire only after both durable authorities
      // are absent; otherwise reset rather than severing a live cleanup fence.
      if (episodeSnapshot.exists || egressSnapshot.exists) {
        return checkpoint({
          transaction,
          reference,
          job,
          Timestamp,
          clock,
          patch: serverDeleting
            ? { contentCleanupChannelPhase: "podcastEpisodes" }
            : { contentCleanupPhase: "podcastEpisodes" },
        });
      }
      transaction.delete(stateReference);
      return checkpoint({ transaction, reference, job, Timestamp, clock, processed: 1 });
    }

    if (phase === "sessions") {
      const sessions = await firstPage(transaction, channelReference.collection("channelSessions"), FieldPathClass, 1);
      if (sessions.empty) return advance();
      const session = sessions.docs[0];
      const value = session.data();
      try {
        assertSessionBinding(value, {
          serverId: job.serverId, channelId: channelReference.id, roomId,
          sessionId: session.id,
        });
      } catch {
        reconciliation();
      }
      if (!["ended", "failed"].includes(value.status)) reconciliation();
      const recipients = await firstPage(transaction, session.ref.collection("tokenRecipients"), FieldPathClass, job.pageSize);
      if (!recipients.empty) {
        recipients.docs.forEach((document) => transaction.delete(document.ref));
        return checkpoint({ transaction, reference, job, Timestamp, clock, processed: recipients.size });
      }
      transaction.delete(session.ref);
      return checkpoint({ transaction, reference, job, Timestamp, clock, processed: 1 });
    }

    if (["roomParticipants", "roomMessages", "roomMembers", "room"].includes(phase)) {
      if (roomId === null) return advance();
      const roomReference = db.doc(`rooms/${roomId}`);
      const roomSnapshot = await transaction.get(roomReference);
      const room = canonicalCleanupRoom(roomSnapshot, {
        serverId: job.serverId, channelId: channelReference.id, roomId,
      });
      if (!serverDeleting && room &&
          (room.status !== "deleting" || room.deletionOperationId !== job.operationId)) reconciliation();
      if (phase === "roomParticipants") {
        const page = await firstPage(transaction, roomReference.collection("participants"), FieldPathClass, job.pageSize);
        const mirrorReferences = page.docs.map((document) => {
          const uid = requireUid(document.id);
          if (!validParticipant(document.data(), { serverId: job.serverId,
            channelId: channelReference.id, roomId, uid })) reconciliation();
          return db.doc(`activeVoiceSessions/${uid}/rooms/${roomId}`);
        });
        const mirrors = mirrorReferences.length
          ? await transactionGetAll(transaction, ...mirrorReferences) : [];
        mirrors.forEach((mirror, index) => {
          if (mirror.exists && !mirrorIsVersionedForAnchor(mirror.data(), {
            serverId: job.serverId, channelId: channelReference.id, roomId,
          }, page.docs[index].id)) reconciliation();
        });
        page.docs.forEach((document, index) => {
          transaction.delete(document.ref);
          if (mirrors[index]?.exists) transaction.delete(mirrors[index].ref);
        });
        return page.empty ? advance() : checkpoint({ transaction, reference, job, Timestamp, clock,
          processed: page.size });
      }
      if (phase === "roomMessages" || phase === "roomMembers") {
        const name = phase === "roomMessages" ? "messages" : "roomMembers";
        const page = await firstPage(transaction, roomReference.collection(name), FieldPathClass, job.pageSize);
        page.docs.forEach((document) => transaction.delete(document.ref));
        return page.empty ? advance() : checkpoint({ transaction, reference, job, Timestamp, clock,
          processed: page.size });
      }
      const probes = await Promise.all([
        emptyProbe(transaction, roomReference.collection("participants"), FieldPathClass),
        emptyProbe(transaction, roomReference.collection("messages"), FieldPathClass),
        emptyProbe(transaction, roomReference.collection("roomMembers"), FieldPathClass),
      ]);
      const occupied = probes.findIndex((probe) => !probe.empty);
      if (occupied >= 0) {
        const reset = ["roomParticipants", "roomMessages", "roomMembers"][occupied];
        return checkpoint({ transaction, reference, job, Timestamp, clock,
          patch: serverDeleting ? { contentCleanupChannelPhase: reset } : { contentCleanupPhase: reset } });
      }
      transaction.delete(roomReference);
      return advance(roomSnapshot.exists ? 1 : 0);
    }

    if (phase !== "final") reconciliation();
    const probes = await Promise.all([
      emptyProbe(transaction, channelReference.collection("accessGrants"), FieldPathClass),
      emptyProbe(transaction, channelReference.collection("messages"), FieldPathClass),
      emptyProbe(transaction, channelReference.collection("events"), FieldPathClass),
      emptyProbe(transaction, channelReference.collection("questions"), FieldPathClass),
      emptyProbe(transaction, channelReference.collection("listItems"), FieldPathClass),
      emptyProbe(transaction, channelReference.collection("whiteboardStrokes"), FieldPathClass),
      emptyProbe(transaction, channelReference.collection("whiteboardState"), FieldPathClass),
      emptyProbe(transaction, channelReference.collection("episodes"), FieldPathClass),
      emptyProbe(transaction, channelReference.collection("podcastRecordingState"), FieldPathClass),
      emptyProbe(transaction, channelReference.collection("files"), FieldPathClass),
      emptyProbe(transaction, channelReference.collection("channelSessions"), FieldPathClass),
    ]);
    const occupied = probes.findIndex((probe) => !probe.empty);
    if (occupied >= 0) {
      const reset = [
        "grants", "messages", "events", "questions", "listItems",
        "whiteboardStrokes", "whiteboardState", "podcastEpisodes",
        "podcastRecordingState", "companyFiles", "sessions",
      ][occupied];
      return checkpoint({ transaction, reference, job, Timestamp, clock,
        patch: serverDeleting ? { contentCleanupChannelPhase: reset } : { contentCleanupPhase: reset } });
    }
    if (roomId !== null && (await transaction.get(db.doc(`rooms/${roomId}`))).exists) {
      return checkpoint({ transaction, reference, job, Timestamp, clock,
        patch: serverDeleting ? { contentCleanupChannelPhase: "roomParticipants" }
          : { contentCleanupPhase: "roomParticipants" } });
    }
    transaction.delete(channelReference);
    if (serverDeleting) {
      return checkpoint({ transaction, reference, job, Timestamp, clock,
        patch: { contentCleanupChannelId: null, contentCleanupChannelPhase: null }, processed: 1 });
    }
    return complete({ transaction, reference, job, Timestamp, clock, processed: 1 });
  }

  async function deleteOrphanRoomPage({ transaction, reference, job, roomReference, phase }) {
    const snapshot = await transaction.get(roomReference);
    const room = canonicalCleanupRoom(snapshot, {
      serverId: job.serverId, channelId: snapshot.data()?.channelId, roomId: roomReference.id,
    });
    if (!room) reconciliation();
    const channelId = requireId(room.channelId, "channelId");
    const advance = () => checkpoint({ transaction, reference, job, Timestamp, clock,
      patch: { contentCleanupRoomPhase: nextPhase(ROOM_PHASES, phase) } });
    if (phase === "participants") {
      const page = await firstPage(transaction, roomReference.collection("participants"), FieldPathClass, job.pageSize);
      const mirrorReferences = page.docs.map((document) => {
        const uid = requireUid(document.id);
        if (!validParticipant(document.data(), { serverId: job.serverId, channelId,
          roomId: roomReference.id, uid })) reconciliation();
        return db.doc(`activeVoiceSessions/${uid}/rooms/${roomReference.id}`);
      });
      const mirrors = mirrorReferences.length
        ? await transactionGetAll(transaction, ...mirrorReferences) : [];
      mirrors.forEach((mirror, index) => {
        if (mirror.exists && !mirrorIsVersionedForAnchor(mirror.data(), {
          serverId: job.serverId, channelId, roomId: roomReference.id,
        }, page.docs[index].id)) reconciliation();
      });
      page.docs.forEach((document, index) => {
        transaction.delete(document.ref);
        if (mirrors[index]?.exists) transaction.delete(mirrors[index].ref);
      });
      return page.empty ? advance() : checkpoint({ transaction, reference, job, Timestamp, clock,
        processed: page.size });
    }
    if (phase === "messages" || phase === "roomMembers") {
      const name = phase === "messages" ? "messages" : "roomMembers";
      const page = await firstPage(transaction, roomReference.collection(name), FieldPathClass, job.pageSize);
      page.docs.forEach((document) => transaction.delete(document.ref));
      return page.empty ? advance() : checkpoint({ transaction, reference, job, Timestamp, clock, processed: page.size });
    }
    if (phase !== "final") reconciliation();
    const probes = await Promise.all([
      emptyProbe(transaction, roomReference.collection("participants"), FieldPathClass),
      emptyProbe(transaction, roomReference.collection("messages"), FieldPathClass),
      emptyProbe(transaction, roomReference.collection("roomMembers"), FieldPathClass),
    ]);
    const occupied = probes.findIndex((probe) => !probe.empty);
    if (occupied >= 0) return checkpoint({ transaction, reference, job, Timestamp, clock,
      patch: { contentCleanupRoomPhase: ROOM_PHASES[occupied] } });
    transaction.delete(roomReference);
    return checkpoint({ transaction, reference, job, Timestamp, clock,
      patch: { contentCleanupRoomId: null, contentCleanupRoomPhase: null }, processed: 1 });
  }

  async function readPodcastEpisodeCleanupAnchor(
    transaction,
    reference,
    operationId,
    pageSize,
  ) {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) reconciliation();
    const job = validateContentCleanupShape({ ...snapshot.data(), pageSize });
    const serverDeleting = job.kind === "serverDelete";
    const expectedPhase = serverDeleting
      ? job.contentCleanupPhase === "channels" &&
        job.contentCleanupChannelPhase === "podcastEpisodes" &&
        job.contentCleanupChannelId !== null
      : job.kind === "channelDelete" && job.contentCleanupPhase === "podcastEpisodes";
    if (job.operationId !== operationId || job.status !== "pending" || !expectedPhase ||
        !["completed", "superseded"].includes(job.grantStatus) ||
        job.rtcStatus !== "completed" || job.rtcTargetIndex !== job.rtcTargets?.length) {
      reconciliation();
    }
    const rootReference = db.doc(`clubs/${job.serverId}`);
    const rootSnapshot = await transaction.get(rootReference);
    let root;
    if (serverDeleting) {
      root = canonicalDeletingRoot(rootSnapshot, job);
    } else {
      root = rootSnapshot.exists ? rootSnapshot.data() : null;
      if (!root || root.serverSchemaVersion !== 1 || root.ownerId !== job.ownerId) {
        reconciliation();
      }
    }
    const channelId = serverDeleting ? job.contentCleanupChannelId : job.channelId;
    const channelReference = rootReference.collection("channels").doc(channelId);
    const channel = canonicalCleanupChannel(
      await transaction.get(channelReference),
      job,
      { serverDeleting },
    );
    if (!serverDeleting && channel.roomId !== job.roomId) reconciliation();
    return { job, root, rootReference, channel, channelReference, serverDeleting };
  }

  async function podcastEpisodeForChannel(transaction, job, channelReference, channel) {
    let page;
    if (channel.kind === "episodes") {
      page = await firstPage(
        transaction,
        channelReference.collection("episodes"),
        FieldPathClass,
        1,
      );
    } else if (channel.kind === "stage") {
      page = await transaction.get(
        db.collectionGroup("episodes")
          .where("serverId", "==", job.serverId)
          .where("studioChannelId", "==", channelReference.id)
          .limit(1),
      );
    } else {
      return null;
    }
    if (page.empty) return null;
    const document = page.docs[0];
    const parentChannel = document.ref.parent.parent;
    const parentServer = parentChannel?.parent.parent;
    const value = document.data() ?? {};
    if (document.ref.parent.id !== "episodes" ||
        parentChannel?.parent.id !== "channels" || parentServer?.parent.id !== "clubs" ||
        parentServer?.id !== job.serverId || parentChannel.id !== value.channelId ||
        (value.channelId !== channelReference.id &&
          value.studioChannelId !== channelReference.id)) {
      reconciliation();
    }
    return document;
  }

  function podcastStateMatchesEpisode(state, episode) {
    return state === null ||
      state.serverId === episode.serverId &&
      state.studioChannelId === episode.studioChannelId &&
      state.channelId === episode.channelId &&
      state.episodeId === episode.episodeId &&
      state.sessionId === episode.sessionId &&
      state.episodeRevision === episode.revision &&
      state.status === episode.status &&
      state.providerStatus === episode.providerStatus;
  }

  function podcastRecordingStateDocument(episode, now) {
    return {
      schemaVersion: 1,
      kind: "podcastRecordingState",
      serverId: episode.serverId,
      studioChannelId: episode.studioChannelId,
      channelId: episode.channelId,
      episodeId: episode.episodeId,
      sessionId: episode.sessionId,
      title: episode.title,
      status: episode.status,
      providerStatus: episode.providerStatus,
      episodeRevision: episode.revision,
      updatedAt: now,
    };
  }

  async function processPodcastEpisodeStoragePage({ operationId, pageSize }) {
    const reference = db.doc(`serverControlOutbox/${operationId}`);
    const leaseId = randomUUID();
    const plan = await db.runTransaction(async (transaction) => {
      const anchor = await readPodcastEpisodeCleanupAnchor(
        transaction,
        reference,
        operationId,
        pageSize,
      );
      const { job, channel, channelReference, serverDeleting } = anchor;
      if (job.bridgeLeaseId !== null && job.bridgeLeaseExpiresAtMillis > clock()) {
        return { busy: true };
      }
      const document = await podcastEpisodeForChannel(
        transaction,
        job,
        channelReference,
        channel,
      );
      if (document === null) {
        return {
          result: checkpoint({
            transaction,
            reference,
            job,
            Timestamp,
            clock,
            patch: serverDeleting
              ? { contentCleanupChannelPhase: "podcastRecordingState" }
              : { contentCleanupPhase: "podcastRecordingState" },
          }),
        };
      }
      const raw = document.data() ?? {};
      const episode = canonicalEpisode(document, {
        serverId: job.serverId,
        channelId: raw.channelId,
        episodeId: document.id,
      });
      const stateReference = db.doc(
        `clubs/${job.serverId}/channels/${episode.studioChannelId}/podcastRecordingState/main`,
      );
      const egressReference = db.doc(`serverPodcastEgressJobs/${episode.episodeId}`);
      const [stateSnapshot, egressSnapshot] = await transactionGetAll(
        transaction,
        stateReference,
        egressReference,
      );
      const state = canonicalRecordingState(stateSnapshot, {
        serverId: episode.serverId,
        studioChannelId: episode.studioChannelId,
      });
      if (!podcastStateMatchesEpisode(state, episode)) reconciliation();

      if (egressSnapshot.exists) {
        const egressJob = canonicalPodcastEgressJob(egressSnapshot, {
          serverId: episode.serverId,
          channelId: episode.channelId,
          studioChannelId: episode.studioChannelId,
          episodeId: episode.episodeId,
          sessionId: episode.sessionId,
          livekitRoomName: episode.livekitRoomName,
          outputPath: episode.outputPath,
        });
        const leaseExpiresAt = egressJob.leaseExpiresAt?.toMillis?.() ?? 0;
        if (egressJob.leaseToken !== null && leaseExpiresAt > clock()) {
          return { busy: true };
        }
        if (egressJob.egressId === null) {
          if (egressJob.action !== "start" || episode.egressId !== null ||
              episode.status !== "recording") reconciliation();
          if (egressJob.nextAttemptAt.toMillis() > clock()) {
            transaction.update(egressReference, {
              nextAttemptAt: Timestamp.fromMillis(clock()),
              lastErrorCode: null,
              updatedAt: Timestamp.fromMillis(clock()),
            });
            return { result: checkpoint({
              transaction, reference, job, Timestamp, clock,
            }) };
          }
          // The Egress reconciler must first discover whether a remote job was
          // created before a crash. Deleting a start job here could strand an
          // unbounded recording whose provider id was never checkpointed.
          return { waiting: true };
        }
        if (!["recording", "processing"].includes(episode.status)) reconciliation();
        if (egressJob.action === "stop") return { waiting: true };
        const now = Timestamp.fromMillis(clock());
        if (episode.status === "recording") {
          const revision = episode.revision + 1;
          if (!validRevision(revision)) reconciliation();
          const stopping = {
            ...episode,
            status: "processing",
            revision,
            providerStatus: "ending",
            stoppedAt: episode.stoppedAt ?? now,
          };
          transaction.update(document.ref, {
            status: stopping.status,
            revision: stopping.revision,
            providerStatus: stopping.providerStatus,
            stoppedAt: stopping.stoppedAt,
            updatedAt: now,
          });
          transaction.set(stateReference, podcastRecordingStateDocument(stopping, now));
        }
        transaction.update(egressReference, {
          action: "stop",
          egressId: egressJob.egressId,
          nextAttemptAt: now,
          leaseToken: null,
          leaseExpiresAt: null,
          lastErrorCode: null,
          updatedAt: now,
        });
        return { result: checkpoint({ transaction, reference, job, Timestamp, clock }) };
      }

      if (!["ready", "published", "error"].includes(episode.status)) reconciliation();
      transaction.update(reference, {
        bridgeLeaseId: leaseId,
        bridgeLeaseExpiresAtMillis: clock() + PODCAST_EPISODE_LEASE_MS,
        updatedAt: Timestamp.fromMillis(clock()),
      });
      return {
        ...anchor,
        step: job.contentCleanupStep,
        task: {
          episode,
          episodeReference: document.ref,
          stateReference,
          egressReference,
        },
      };
    });
    if (plan.busy || plan.waiting) return cleanupResult();
    if (plan.result) return plan.result;
    if (!podcastEpisodeStorage?.deleteUnpublished) reconciliation();

    try {
      await podcastEpisodeStorage.deleteUnpublished(plan.task.episode.outputPath, {
        generation: plan.task.episode.media?.generation ?? null,
      });
    } catch (error) {
      await db.runTransaction(async (transaction) => {
        const current = await transaction.get(reference);
        if (current.exists && current.data()?.bridgeLeaseId === leaseId) {
          transaction.update(reference, {
            bridgeLeaseId: null,
            bridgeLeaseExpiresAtMillis: 0,
            retryAfterMillis: clock() + 30_000,
            lastErrorCode: "unavailable",
            updatedAt: Timestamp.fromMillis(clock()),
          });
        }
      });
      throw error;
    }

    return db.runTransaction(async (transaction) => {
      const anchor = await readPodcastEpisodeCleanupAnchor(
        transaction,
        reference,
        operationId,
        pageSize,
      );
      const [episodeSnapshot, stateSnapshot, egressSnapshot] = await transactionGetAll(
        transaction,
        plan.task.episodeReference,
        plan.task.stateReference,
        plan.task.egressReference,
      );
      if (anchor.job.contentCleanupStep !== plan.step ||
          anchor.job.bridgeLeaseId !== leaseId || !episodeSnapshot.exists ||
          egressSnapshot.exists) reconciliation();
      const current = canonicalEpisode(episodeSnapshot, {
        serverId: plan.task.episode.serverId,
        channelId: plan.task.episode.channelId,
        episodeId: plan.task.episode.episodeId,
      });
      if (current.revision !== plan.task.episode.revision ||
          current.status !== plan.task.episode.status ||
          current.outputPath !== plan.task.episode.outputPath ||
          JSON.stringify(current.media) !== JSON.stringify(plan.task.episode.media)) {
        reconciliation();
      }
      const state = canonicalRecordingState(stateSnapshot, {
        serverId: current.serverId,
        studioChannelId: current.studioChannelId,
      });
      if (!podcastStateMatchesEpisode(state, current)) reconciliation();
      transaction.delete(plan.task.episodeReference);
      if (stateSnapshot.exists) transaction.delete(plan.task.stateReference);
      return checkpoint({
        transaction,
        reference,
        job: anchor.job,
        Timestamp,
        clock,
        patch: {
          bridgeLeaseId: null,
          bridgeLeaseExpiresAtMillis: 0,
          retryAfterMillis: 0,
          lastErrorCode: null,
        },
        processed: 1,
      });
    });
  }

  async function readCompanyFileCleanupAnchor(
    transaction,
    reference,
    operationId,
    pageSize,
  ) {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) reconciliation();
    const job = validateContentCleanupShape({ ...snapshot.data(), pageSize });
    const serverDeleting = job.kind === "serverDelete";
    const expectedPhase = serverDeleting
      ? job.contentCleanupPhase === "channels" &&
        job.contentCleanupChannelPhase === "companyFiles" &&
        job.contentCleanupChannelId !== null
      : job.kind === "channelDelete" && job.contentCleanupPhase === "companyFiles";
    if (job.operationId !== operationId || job.status !== "pending" || !expectedPhase ||
        !["completed", "superseded"].includes(job.grantStatus) ||
        job.rtcStatus !== "completed" || job.rtcTargetIndex !== job.rtcTargets?.length) {
      reconciliation();
    }
    const rootReference = db.doc(`clubs/${job.serverId}`);
    const rootSnapshot = await transaction.get(rootReference);
    let root;
    if (serverDeleting) {
      root = canonicalDeletingRoot(rootSnapshot, job);
    } else {
      root = rootSnapshot.exists ? rootSnapshot.data() : null;
      if (!root || root.serverSchemaVersion !== 1 || root.ownerId !== job.ownerId) {
        reconciliation();
      }
    }
    const channelId = serverDeleting ? job.contentCleanupChannelId : job.channelId;
    const channelReference = rootReference.collection("channels").doc(channelId);
    const channel = canonicalCleanupChannel(
      await transaction.get(channelReference),
      job,
      { serverDeleting },
    );
    if (!serverDeleting && channel.roomId !== job.roomId) reconciliation();
    return { job, root, rootReference, channel, channelReference, serverDeleting };
  }

  async function processCompanyFileStoragePage({ operationId, pageSize }) {
    const reference = db.doc(`serverControlOutbox/${operationId}`);
    const leaseId = randomUUID();
    const plan = await db.runTransaction(async (transaction) => {
      const anchor = await readCompanyFileCleanupAnchor(
        transaction,
        reference,
        operationId,
        pageSize,
      );
      const { job, channelReference, serverDeleting } = anchor;
      if (job.bridgeLeaseId !== null && job.bridgeLeaseExpiresAtMillis > clock()) {
        return { busy: true };
      }

      const [reservations, deletionJobs, files] = await Promise.all([
        transaction.get(db.collection("serverCompanyFileUploadReservations")
          .where("serverId", "==", job.serverId)
          .where("channelId", "==", channelReference.id)
          .limit(1)),
        transaction.get(db.collection("serverCompanyFileDeletionJobs")
          .where("serverId", "==", job.serverId)
          .where("channelId", "==", channelReference.id)
          .limit(1)),
        firstPage(transaction, channelReference.collection("files"), FieldPathClass, 1),
      ]);

      let task = null;
      if (!reservations.empty) {
        const document = reservations.docs[0];
        const raw = document.data() ?? {};
        const reservation = canonicalCompanyFileReservation(document, {
          serverId: job.serverId,
          channelId: channelReference.id,
          fileId: document.id,
          ownerId: raw.ownerId,
          reserveRequestId: raw.requestId,
        }, clock(), { allowExpiring: true });
        const leaseReference = db.doc(`serverCompanyFileUploadLeases/${reservation.ownerId}`);
        const lease = await transaction.get(leaseReference);
        if (reservation.status === "uploading") {
          transaction.update(document.ref, {
            status: "expiring",
            updatedAt: Timestamp.fromMillis(clock()),
          });
        }
        task = {
          kind: "reservation",
          reservation: { ...reservation, status: "expiring" },
          reservationReference: document.ref,
          leaseReference,
          leaseExists: lease.exists,
        };
      } else if (!deletionJobs.empty) {
        const document = deletionJobs.docs[0];
        const deletion = canonicalCompanyFileDeletionJob(document, {
          serverId: job.serverId,
          channelId: channelReference.id,
        });
        const fileReference = channelReference.collection("files").doc(deletion.fileId);
        const fileSnapshot = await transaction.get(fileReference);
        if (fileSnapshot.exists) {
          const file = canonicalCompanyFile(fileSnapshot, deletion, { allowDeleting: true });
          if (file.status !== "deleting" ||
              file.deletionOperationId !== deletion.deletionOperationId ||
              file.revision !== deletion.deletionRevision ||
              file.ownerId !== deletion.ownerId ||
              JSON.stringify(file.file) !== JSON.stringify(deletion.file)) {
            reconciliation();
          }
        }
        task = {
          kind: "deletion",
          deletion,
          deletionReference: document.ref,
          fileReference,
        };
      } else if (!files.empty) {
        const document = files.docs[0];
        const file = canonicalCompanyFile(document, {
          serverId: job.serverId,
          channelId: channelReference.id,
          fileId: document.id,
        }, { allowDeleting: true });
        const deletionReference = db.doc(
          `serverCompanyFileDeletionJobs/${companyFileDeletionJobId(
            job.serverId,
            channelReference.id,
            document.id,
          )}`,
        );
        const deletionSnapshot = await transaction.get(deletionReference);
        let deletion;
        if (file.status === "deleting") {
          deletion = canonicalCompanyFileDeletionJob(deletionSnapshot, {
            serverId: job.serverId,
            channelId: channelReference.id,
            fileId: document.id,
          });
          if (file.deletionOperationId !== deletion.deletionOperationId ||
              file.revision !== deletion.deletionRevision ||
              file.ownerId !== deletion.ownerId ||
              JSON.stringify(file.file) !== JSON.stringify(deletion.file)) {
            reconciliation();
          }
        } else {
          if (deletionSnapshot.exists || !validRevision(file.revision + 1)) reconciliation();
          const now = Timestamp.fromMillis(clock());
          deletion = {
            schemaVersion: 1,
            kind: "serverCompanyFileDelete",
            jobId: deletionReference.id,
            serverId: job.serverId,
            channelId: channelReference.id,
            fileId: document.id,
            ownerId: file.ownerId,
            requestedBy: job.requestedBy,
            deletionOperationId: job.operationId,
            deletionRevision: file.revision + 1,
            file: file.file,
            status: "pending",
            createdAt: now,
            updatedAt: now,
          };
          transaction.update(document.ref, {
            status: "deleting",
            deletionOperationId: job.operationId,
            deletionRequestedBy: job.requestedBy,
            revision: deletion.deletionRevision,
            updatedAt: now,
          });
          transaction.create(deletionReference, deletion);
        }
        task = {
          kind: "deletion",
          deletion,
          deletionReference,
          fileReference: document.ref,
        };
      }

      if (task === null) {
        return {
          result: checkpoint({
            transaction,
            reference,
            job,
            Timestamp,
            clock,
            patch: serverDeleting
              ? { contentCleanupChannelPhase: nextPhase(CHANNEL_PHASES, "companyFiles") }
              : { contentCleanupPhase: nextPhase(CHANNEL_PHASES, "companyFiles") },
          }),
        };
      }
      transaction.update(reference, {
        bridgeLeaseId: leaseId,
        bridgeLeaseExpiresAtMillis: clock() + COMPANY_FILE_LEASE_MS,
        updatedAt: Timestamp.fromMillis(clock()),
      });
      return { ...anchor, step: job.contentCleanupStep, task };
    });
    if (plan.busy) return cleanupResult();
    if (plan.result) return plan.result;
    if (!companyFileStorage?.deleteObject) reconciliation();

    try {
      if (plan.task.kind === "reservation") {
        await companyFileStorage.deleteObject(plan.task.reservation.storagePath);
      } else {
        await companyFileStorage.deleteObject(plan.task.deletion.file.storagePath, {
          generation: plan.task.deletion.file.generation,
        });
      }
    } catch (error) {
      await db.runTransaction(async (transaction) => {
        const current = await transaction.get(reference);
        if (current.exists && current.data()?.bridgeLeaseId === leaseId) {
          transaction.update(reference, {
            bridgeLeaseId: null,
            bridgeLeaseExpiresAtMillis: 0,
            retryAfterMillis: clock() + 30_000,
            lastErrorCode: "unavailable",
            updatedAt: Timestamp.fromMillis(clock()),
          });
        }
      });
      throw error;
    }

    return db.runTransaction(async (transaction) => {
      const anchor = await readCompanyFileCleanupAnchor(
        transaction,
        reference,
        operationId,
        pageSize,
      );
      if (anchor.job.contentCleanupStep !== plan.step ||
          anchor.job.bridgeLeaseId !== leaseId) reconciliation();
      if (plan.task.kind === "reservation") {
        const [reservationSnapshot, leaseSnapshot] = await transactionGetAll(
          transaction,
          plan.task.reservationReference,
          plan.task.leaseReference,
        );
        if (reservationSnapshot.exists) {
          const reservation = canonicalCompanyFileReservation(reservationSnapshot, {
            serverId: plan.task.reservation.serverId,
            channelId: plan.task.reservation.channelId,
            fileId: plan.task.reservation.fileId,
            ownerId: plan.task.reservation.ownerId,
            reserveRequestId: plan.task.reservation.requestId,
          }, clock(), { allowExpiring: true });
          if (reservation.status !== "expiring" ||
              reservation.storagePath !== plan.task.reservation.storagePath) {
            reconciliation();
          }
          transaction.delete(plan.task.reservationReference);
        }
        if (leaseSnapshot.exists &&
            leaseSnapshot.data()?.ownerId === plan.task.reservation.ownerId &&
            leaseSnapshot.data()?.fileId === plan.task.reservation.fileId) {
          if (leaseSnapshot.data()?.serverId !== plan.task.reservation.serverId ||
              leaseSnapshot.data()?.channelId !== plan.task.reservation.channelId) {
            reconciliation();
          }
          transaction.delete(plan.task.leaseReference);
        }
      } else {
        const [deletionSnapshot, fileSnapshot] = await transactionGetAll(
          transaction,
          plan.task.deletionReference,
          plan.task.fileReference,
        );
        if (!deletionSnapshot.exists) {
          if (fileSnapshot.exists) reconciliation();
        } else {
          const deletion = canonicalCompanyFileDeletionJob(deletionSnapshot, {
            serverId: plan.task.deletion.serverId,
            channelId: plan.task.deletion.channelId,
            fileId: plan.task.deletion.fileId,
          });
          if (deletion.deletionOperationId !== plan.task.deletion.deletionOperationId ||
              deletion.deletionRevision !== plan.task.deletion.deletionRevision ||
              deletion.ownerId !== plan.task.deletion.ownerId ||
              JSON.stringify(deletion.file) !== JSON.stringify(plan.task.deletion.file)) {
            reconciliation();
          }
          if (fileSnapshot.exists) {
            const file = canonicalCompanyFile(fileSnapshot, deletion, { allowDeleting: true });
            if (file.status !== "deleting" ||
                file.deletionOperationId !== deletion.deletionOperationId ||
                file.revision !== deletion.deletionRevision ||
                file.ownerId !== deletion.ownerId ||
                JSON.stringify(file.file) !== JSON.stringify(deletion.file)) {
              reconciliation();
            }
            transaction.delete(plan.task.fileReference);
          }
          transaction.delete(plan.task.deletionReference);
        }
      }
      return checkpoint({
        transaction,
        reference,
        job: anchor.job,
        Timestamp,
        clock,
        patch: {
          bridgeLeaseId: null,
          bridgeLeaseExpiresAtMillis: 0,
          retryAfterMillis: 0,
          lastErrorCode: null,
        },
        processed: 1,
      });
    });
  }

  async function processFamilyMemoryStoragePage({ operationId, pageSize }) {
    if (!familyMemoryStorage?.listObjects || !familyMemoryStorage?.deleteObject) reconciliation();
    const reference = db.doc(`serverControlOutbox/${operationId}`);
    const leaseId = randomUUID();
    const plan = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) reconciliation();
      const job = validateContentCleanupShape({ ...snapshot.data(), pageSize });
      if (job.operationId !== operationId || job.kind !== "serverDelete" ||
          job.status !== "pending" || job.contentCleanupPhase !== "familyMemoryStorage" ||
          !["completed", "superseded"].includes(job.grantStatus) ||
          job.rtcStatus !== "completed" || job.rtcTargetIndex !== job.rtcTargets?.length) {
        reconciliation();
      }
      const rootReference = db.doc(`clubs/${job.serverId}`);
      canonicalDeletingRoot(await transaction.get(rootReference), job);
      if (job.bridgeLeaseId !== null && job.bridgeLeaseExpiresAtMillis > clock()) {
        return { busy: true };
      }
      transaction.update(reference, {
        bridgeLeaseId: leaseId,
        bridgeLeaseExpiresAtMillis: clock() + FAMILY_MEMORY_LEASE_MS,
        updatedAt: Timestamp.fromMillis(clock()),
      });
      return {
        job,
        rootReference,
        step: job.contentCleanupStep,
        prefix: `${FAMILY_MEMORY_PREFIX}/${job.serverId}/`,
      };
    });
    if (plan.busy) return cleanupResult();
    let objects;
    try {
      objects = await familyMemoryStorage.listObjects(plan.prefix, { maxResults: pageSize });
      if (!Array.isArray(objects) || objects.length > pageSize) reconciliation();
      for (const object of objects) {
        canonicalFamilyMemoryPath(object?.name, plan.job.serverId);
        if (typeof object.generation !== "string" ||
            !GENERATION_PATTERN.test(object.generation)) reconciliation();
      }
      await Promise.all(objects.map((object) => familyMemoryStorage.deleteObject(
        object.name,
        { generation: object.generation },
      )));
    } catch (error) {
      await db.runTransaction(async (transaction) => {
        const current = await transaction.get(reference);
        if (current.exists && current.data()?.bridgeLeaseId === leaseId) {
          transaction.update(reference, {
            bridgeLeaseId: null,
            bridgeLeaseExpiresAtMillis: 0,
            retryAfterMillis: clock() + 30_000,
            lastErrorCode: "unavailable",
            updatedAt: Timestamp.fromMillis(clock()),
          });
        }
      });
      throw error;
    }

    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) reconciliation();
      const current = validateContentCleanupShape({ ...snapshot.data(), pageSize });
      if (current.operationId !== operationId || current.kind !== "serverDelete" ||
          current.status !== "pending" || current.contentCleanupPhase !== "familyMemoryStorage" ||
          current.contentCleanupStep !== plan.step || current.bridgeLeaseId !== leaseId) {
        reconciliation();
      }
      canonicalDeletingRoot(await transaction.get(plan.rootReference), current);
      return checkpoint({
        transaction,
        reference,
        job: current,
        Timestamp,
        clock,
        patch: {
          ...(objects.length === 0 ? { contentCleanupPhase: "checkIns" } : {}),
          bridgeLeaseId: null,
          bridgeLeaseExpiresAtMillis: 0,
          retryAfterMillis: 0,
          lastErrorCode: null,
        },
        processed: objects.length,
      });
    });
  }

  async function processServerContentCleanupPage({ operationId, pageSize = 20 }) {
    requireId(operationId, "operationId");
    requireSafeInteger(pageSize, "pageSize", { min: 1, max: 20 });
    const reference = db.doc(`serverControlOutbox/${operationId}`);
    const phaseSnapshot = await reference.get();
    const phase = phaseSnapshot.exists ? (phaseSnapshot.data() ?? {}) : {};
    const podcastEpisodePhase =
      phase.status === "pending" &&
      (phase.kind === "channelDelete" && phase.contentCleanupPhase === "podcastEpisodes" ||
        phase.kind === "serverDelete" && phase.contentCleanupPhase === "channels" &&
          phase.contentCleanupChannelPhase === "podcastEpisodes");
    if (podcastEpisodePhase) {
      return processPodcastEpisodeStoragePage({ operationId, pageSize });
    }
    const companyFilePhase =
      phase.status === "pending" &&
      (phase.kind === "channelDelete" && phase.contentCleanupPhase === "companyFiles" ||
        phase.kind === "serverDelete" && phase.contentCleanupPhase === "channels" &&
          phase.contentCleanupChannelPhase === "companyFiles");
    if (companyFilePhase) {
      return processCompanyFileStoragePage({ operationId, pageSize });
    }
    if (phaseSnapshot.exists && phaseSnapshot.data()?.status === "pending" &&
        phaseSnapshot.data()?.kind === "serverDelete" &&
        phaseSnapshot.data()?.contentCleanupPhase === "familyMemoryStorage") {
      return processFamilyMemoryStoragePage({ operationId, pageSize });
    }
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) reconciliation();
      const raw = snapshot.data();
      if (raw.status === "completed" && raw.contentCleanupPending === false) {
        if (!["channelDelete", "serverDelete"].includes(raw.kind) || raw.operationId !== operationId ||
            raw.contentCleanupVersion !== CONTENT_CLEANUP_VERSION || !validRevision(raw.deletionRevision) ||
            !Number.isSafeInteger(raw.contentCleanupStep)) reconciliation();
        return cleanupResult({ complete: true });
      }
      const job = validateContentCleanupShape({ ...raw, pageSize });
      if (job.operationId !== operationId || job.status !== "pending" ||
          !["completed", "superseded"].includes(job.grantStatus) || job.rtcStatus !== "completed" ||
          job.rtcTargetIndex !== job.rtcTargets?.length || job.bridgeLeaseId !== null) reconciliation();
      const rootReference = db.doc(`clubs/${job.serverId}`);
      const rootSnapshot = await transaction.get(rootReference);

      if (job.kind === "channelDelete") {
        const root = rootSnapshot.exists ? rootSnapshot.data() : null;
        if (!root || root.serverSchemaVersion !== 1 || root.ownerId !== job.ownerId) reconciliation();
        const channelReference = rootReference.collection("channels").doc(job.channelId);
        const channelSnapshot = await transaction.get(channelReference);
        const channel = canonicalCleanupChannel(channelSnapshot, job, { serverDeleting: false });
        if (channel.roomId !== job.roomId) reconciliation();
        return deleteChannelPage({ transaction, reference, job, root, channelReference,
          channel, phase: job.contentCleanupPhase, serverDeleting: false });
      }

      const root = canonicalDeletingRoot(rootSnapshot, job);
      if (job.contentCleanupPhase === "channels") {
        if (job.contentCleanupChannelId === null) {
          const page = await firstPage(transaction, rootReference.collection("channels"), FieldPathClass, 1);
          if (page.empty) {
            // Every channel is gone: sweep the whole server prefix once more,
            // which also reaches objects of channels deleted long ago.
            enqueueServerMessageMediaSweep(db, transaction, {
              serverId: job.serverId, channelId: null, reason: "serverDelete",
              now: Timestamp.fromMillis(clock()),
            });
            return checkpoint({ transaction, reference, job, Timestamp, clock,
              patch: { contentCleanupPhase: "orphanRooms" } });
          }
          const channel = canonicalCleanupChannel(page.docs[0], job, { serverDeleting: true });
          if (channel.deletionOperationId && channel.deletionOperationId !== job.operationId) {
            const owner = await transaction.get(db.doc(`serverControlOutbox/${channel.deletionOperationId}`));
            const other = owner.exists ? owner.data() : null;
            if (!other || other.kind !== "channelDelete" || other.serverId !== job.serverId ||
                other.channelId !== page.docs[0].id || other.status !== "pending") reconciliation();
            return cleanupResult();
          }
          return checkpoint({ transaction, reference, job, Timestamp, clock,
            patch: { contentCleanupChannelId: page.docs[0].id, contentCleanupChannelPhase: CHANNEL_PHASES[0] } });
        }
        const channelReference = rootReference.collection("channels").doc(job.contentCleanupChannelId);
        const channelSnapshot = await transaction.get(channelReference);
        const channel = canonicalCleanupChannel(channelSnapshot, job, { serverDeleting: true });
        return deleteChannelPage({ transaction, reference, job, root, channelReference, channel,
          phase: job.contentCleanupChannelPhase, serverDeleting: true });
      }

      if (job.contentCleanupPhase === "orphanRooms") {
        if (job.contentCleanupRoomId === null) {
          const rooms = await transaction.get(db.collection("rooms").where("serverId", "==", job.serverId).limit(1));
          if (rooms.empty) return checkpoint({ transaction, reference, job, Timestamp, clock,
            patch: { contentCleanupPhase: "invites" } });
          canonicalCleanupRoom(rooms.docs[0], { serverId: job.serverId,
            channelId: rooms.docs[0].data()?.channelId, roomId: rooms.docs[0].id });
          return checkpoint({ transaction, reference, job, Timestamp, clock,
            patch: { contentCleanupRoomId: rooms.docs[0].id, contentCleanupRoomPhase: ROOM_PHASES[0] } });
        }
        return deleteOrphanRoomPage({ transaction, reference, job,
          roomReference: db.doc(`rooms/${job.contentCleanupRoomId}`), phase: job.contentCleanupRoomPhase });
      }

      if (job.contentCleanupPhase === "invites") {
        const page = await firstPage(transaction, rootReference.collection("invites"), FieldPathClass, pageSize);
        const mirrorReferences = page.docs.map((document) => {
          const uid = requireUid(document.id);
          const invite = document.data();
          if (invite.serverId !== job.serverId || invite.inviteeId !== uid) reconciliation();
          return db.doc(serverInviteRefPath(uid, job.serverId));
        });
        const mirrors = mirrorReferences.length
          ? await transactionGetAll(transaction, ...mirrorReferences) : [];
        page.docs.forEach((document, index) => {
          transaction.delete(document.ref);
          if (mirrors[index]?.exists) transaction.delete(mirrors[index].ref);
        });
        return page.empty ? checkpoint({ transaction, reference, job, Timestamp, clock,
          patch: { contentCleanupPhase: "members" } })
          : checkpoint({ transaction, reference, job, Timestamp, clock, processed: page.size });
      }

      if (job.contentCleanupPhase === "members") {
        const page = await firstPage(transaction, rootReference.collection("members"), FieldPathClass, pageSize);
        page.docs.forEach((document) => {
          const uid = requireUid(document.id);
          if (document.data()?.userId !== uid) reconciliation();
        });
        page.docs.forEach((document) => {
          transaction.delete(document.ref);
          transaction.delete(rootReference.collection("memberAuthorizations").doc(document.id));
          transaction.delete(db.doc(`users/${document.id}/clubs/${job.serverId}`));
        });
        return page.empty ? checkpoint({ transaction, reference, job, Timestamp, clock,
          patch: { contentCleanupPhase: "memberAuthorizations" } })
          : checkpoint({ transaction, reference, job, Timestamp, clock, processed: page.size });
      }

      if (job.contentCleanupPhase === "familyMemoryReservations") {
        const page = await transaction.get(db.collection("serverFamilyMemoryUploadReservations")
          .where("serverId", "==", job.serverId)
          .orderBy(FieldPathClass.documentId()).limit(pageSize));
        const values = page.docs.map((document) =>
          canonicalFamilyMemoryReservation(document, job.serverId));
        const leaseReferences = values.map((value) =>
          db.doc(`serverFamilyMemoryUploadLeases/${value.ownerId}`));
        const leases = leaseReferences.length
          ? await transactionGetAll(transaction, ...leaseReferences) : [];
        leases.forEach((lease, index) => {
          if (!lease.exists) return;
          const value = leases[index].data() ?? {};
          const reservation = values[index];
          if (value.ownerId === reservation.ownerId && value.memoryId === reservation.memoryId) {
            if (value.serverId !== job.serverId) reconciliation();
            transaction.delete(lease.ref);
          }
        });
        page.docs.forEach((document) => transaction.delete(document.ref));
        return page.empty ? checkpoint({ transaction, reference, job, Timestamp, clock,
          patch: { contentCleanupPhase: "familyMemoryDeletionJobs" } })
          : checkpoint({ transaction, reference, job, Timestamp, clock, processed: page.size });
      }

      if (job.contentCleanupPhase === "familyMemoryDeletionJobs") {
        const page = await transaction.get(db.collection("serverFamilyMemoryDeletionJobs")
          .where("serverId", "==", job.serverId)
          .orderBy(FieldPathClass.documentId()).limit(pageSize));
        page.docs.forEach((document) => {
          canonicalFamilyMemoryDeletionJob(document, job.serverId);
          transaction.delete(document.ref);
        });
        return page.empty ? checkpoint({ transaction, reference, job, Timestamp, clock,
          patch: { contentCleanupPhase: "familyMemoryStorage" } })
          : checkpoint({ transaction, reference, job, Timestamp, clock, processed: page.size });
      }

      if (job.contentCleanupPhase === "followers") {
        const page = await firstPage(transaction,
          rootReference.collection("followers"), FieldPathClass, pageSize);
        const values = page.docs.map((document) => {
          const value = canonicalServerFollow(document, job.serverId);
          if (value.userId !== document.id) reconciliation();
          return value;
        });
        const mirrors = values.length ? await transactionGetAll(transaction,
          ...values.map((value) => db.doc(`users/${value.userId}/serverFollows/${job.serverId}`))) : [];
        mirrors.forEach((mirror, index) => {
          if (!mirror.exists) return;
          const mirrorValue = canonicalServerFollow(mirror, job.serverId);
          if (mirrorValue.userId !== values[index].userId) reconciliation();
          transaction.delete(mirror.ref);
        });
        page.docs.forEach((document) => transaction.delete(document.ref));
        return page.empty ? checkpoint({ transaction, reference, job, Timestamp, clock,
          patch: { contentCleanupPhase: "followMirrors" } })
          : checkpoint({ transaction, reference, job, Timestamp, clock, processed: page.size });
      }

      if (job.contentCleanupPhase === "followMirrors") {
        const page = await transaction.get(db.collectionGroup("serverFollows")
          .where("serverId", "==", job.serverId)
          .orderBy(FieldPathClass.documentId()).limit(pageSize));
        page.docs.forEach((document) => {
          const value = canonicalServerFollow(document, job.serverId);
          if (document.id !== job.serverId ||
              document.ref.parent.parent?.id !== value.userId ||
              document.ref.parent.id !== "serverFollows") reconciliation();
          transaction.delete(document.ref);
        });
        return page.empty ? checkpoint({ transaction, reference, job, Timestamp, clock,
          patch: { contentCleanupPhase: "bans" } })
          : checkpoint({ transaction, reference, job, Timestamp, clock, processed: page.size });
      }

      if (LOCAL_SERVER_COLLECTIONS.includes(job.contentCleanupPhase)) {
        const page = await firstPage(transaction,
          rootReference.collection(job.contentCleanupPhase), FieldPathClass, pageSize);
        page.docs.forEach((document) => transaction.delete(document.ref));
        return page.empty ? checkpoint({ transaction, reference, job, Timestamp, clock,
          patch: { contentCleanupPhase: nextPhase(SERVER_PHASES, job.contentCleanupPhase) } })
          : checkpoint({ transaction, reference, job, Timestamp, clock, processed: page.size });
      }

      if (job.contentCleanupPhase !== "final") reconciliation();
      const [companyReservations, companyDeletionJobs, podcastEgressJobs] = await Promise.all([
        transaction.get(db.collection("serverCompanyFileUploadReservations")
          .where("serverId", "==", job.serverId).limit(1)),
        transaction.get(db.collection("serverCompanyFileDeletionJobs")
          .where("serverId", "==", job.serverId).limit(1)),
        transaction.get(db.collection("serverPodcastEgressJobs")
          .where("serverId", "==", job.serverId).limit(1)),
      ]);
      // Every valid Company File reference is drained while its channel is
      // still present. Reaching the root fence with an orphaned global record
      // is corruption, not authority to delete an unverified object path.
      if (!companyReservations.empty || !companyDeletionJobs.empty ||
          !podcastEgressJobs.empty) reconciliation();
      const probes = await Promise.all([
        emptyProbe(transaction, rootReference.collection("channels"), FieldPathClass),
        transaction.get(db.collection("rooms").where("serverId", "==", job.serverId).limit(1)),
        emptyProbe(transaction, rootReference.collection("invites"), FieldPathClass),
        emptyProbe(transaction, rootReference.collection("members"), FieldPathClass),
        ...LOCAL_SERVER_COLLECTIONS.map((name) =>
          emptyProbe(transaction, rootReference.collection(name), FieldPathClass)),
        transaction.get(db.collection("serverFamilyMemoryUploadReservations")
          .where("serverId", "==", job.serverId).limit(1)),
        transaction.get(db.collection("serverFamilyMemoryDeletionJobs")
          .where("serverId", "==", job.serverId).limit(1)),
        emptyProbe(transaction, rootReference.collection("followers"), FieldPathClass),
        transaction.get(db.collectionGroup("serverFollows")
          .where("serverId", "==", job.serverId).limit(1)),
      ]);
      const reset = ["channels", "orphanRooms", "invites", "members", ...LOCAL_SERVER_COLLECTIONS,
        "familyMemoryReservations", "familyMemoryDeletionJobs", "followers", "followMirrors"]
        .find((_, index) => !probes[index].empty);
      if (reset) return checkpoint({ transaction, reference, job, Timestamp, clock,
        patch: { contentCleanupPhase: reset } });
      transaction.delete(db.doc(`users/${job.ownerId}/clubs/${job.serverId}`));
      transaction.delete(rootReference);
      return complete({ transaction, reference, job, Timestamp, clock, processed: 1 });
    });
  }

  return { processServerContentCleanupPage };
}

module.exports = {
  CHANNEL_PHASES,
  CONTENT_CLEANUP_VERSION,
  ROOM_PHASES,
  SERVER_PHASES,
  createServerContentCleanupService,
  deletionCleanupState,
  validateContentCleanupShape,
};
