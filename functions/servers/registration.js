// Servers V1 registration and durable dispatch (ADR-176).
//
// This is the only module that turns the reviewed, frozen factories under
// functions/servers/* into Cloud Functions endpoints. functions/index.js
// registers the base map statically because Firebase discovers exports before
// loading functions/.env. Runtime use stays fail-closed behind the server-owned
// activation document below, so deployment and activation remain separate.
//
// What this module does NOT do, on purpose:
//   - it never writes to Firestore itself. Every mutation is a reviewed
//     factory method; the dispatcher only reads `serverControlOutbox/{id}` to
//     decide whether asking a worker is worthwhile, and every worker takes
//     its own lease and revalidates the job inside its own transaction;
//   - it never completes uncertain work. Worker outcomes are checkpointed and
//     retried only through the reviewed bounded workers;
//   - it has no general activation writer. The exact registration boundary may
//     create a brand-new V1 graph active in its seed transaction; an existing
//     held or migrated root is never changed by that capability.

const { FieldPath, Timestamp, getFirestore } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { randomBytes } = require("node:crypto");
const { logger } = require("firebase-functions/v2");
const { defineSecret, defineString } = require("firebase-functions/params");
const { HttpsError, onCall } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const { requireActor, requireId, requireSafeInteger } = require("../integrity/guards");
const { createTrustedGcsMediaProbe } = require("../reels/probe");
const { createLazyBucket } = require("../utils/lazy_bucket");
const { createServerCreationService } = require("./creation");
const { createServerChannelService } = require("./channels");
const { createServerEventService } = require("./events");
const { createServerPodcastQuestionService } = require("./podcast_questions");
const {
  createLiveKitPodcastEgressAdapter,
  createPodcastEpisodeStorageAdapter,
  createServerPodcastEpisodeService,
} = require("./podcast_episodes");
const { createServerSharedListService } = require("./shared_list");
const { createServerFamilyCheckInService } = require("./family_checkins");
const {
  createFamilyMemoryStorageAdapter,
  createServerFamilyMemoryService,
} = require("./family_memories");
const { createServerFollowService } = require("./follows");
const { createServerWhiteboardService } = require("./whiteboard");
const {
  createCompanyFileStorageAdapter,
  createServerCompanyFileService,
} = require("./company_files");
const { createServerInviteService } = require("./invites");
const { createServerMembershipService } = require("./memberships");
const {
  createServerRolePromotionNotifier,
} = require("../notifications/server_roles");
const { createServerManagementService } = require("./management");
const { createServerSessionService } = require("./sessions");
const { createServerCommunityBroadcastService } = require("./community_broadcast");
const { createServerSessionParticipationService } = require("./session_participation");
const { createServerSessionStalenessService } = require("./session_staleness");
const { createServerConvergenceService } = require("./convergence");
const { createServerConvergenceRuntimeService } = require("./convergence_runtime");
const { createServerSessionControlService } = require("./session_control");
const { createServerLiveKitAdapter } = require("./session_livekit");
const { createServerMessageReactionService } = require("./message_reactions");
const {
  createServerMessageMediaService,
  createServerMessageMediaStorageAdapter,
} = require("./message_media");

const REGION = "europe-west1";
const OUTBOX_COLLECTION = "serverControlOutbox";
const ACTIVATION_CONFIG_PATH = "appConfig/serversV1";
const ACTIVATION_ACCESS = Object.freeze(["disabled", "testers", "all"]);
const ACTIVATION_UNAVAILABLE_REASON = "servers-v1-not-enabled";
const MAX_ACTIVATION_TESTERS = 100;

// The fifty-four V1 callables of docs/Servers.md "Callable contract", in that
// order, each bound to the reviewed factory that implements it. The export
// name and the factory method name are deliberately identical, so a typo in
// this table is a TypeError at deploy discovery, never a NOT_FOUND in a client.
// test/servers_registration_independent_qa.test.js parses the documented
// table and asserts this map lists exactly those names in that order.
const SERVER_CALLABLE_METHODS = Object.freeze({
  createServerV1: "creation",
  updateServerV1: "channels",
  deleteServerV1: "management",
  createServerChannelV1: "channels",
  updateServerChannelV1: "channels",
  reorderServerChannelsV1: "channels",
  setServerChannelAccessV1: "channels",
  archiveServerChannelV1: "channels",
  deleteServerChannelV1: "channels",
  createServerEventV1: "events",
  updateServerEventV1: "events",
  cancelServerEventV1: "events",
  respondToServerEventV1: "events",
  createServerPodcastQuestionV1: "podcastQuestions",
  setServerPodcastQuestionVoteV1: "podcastQuestions",
  setServerPodcastQuestionOnAirV1: "podcastQuestions",
  startServerPodcastRecordingV1: "podcastEpisodes",
  stopServerPodcastRecordingV1: "podcastEpisodes",
  finalizeServerPodcastEpisodeV1: "podcastEpisodes",
  retryServerPodcastRecordingV1: "podcastEpisodes",
  publishServerPodcastEpisodeV1: "podcastEpisodes",
  getServerPodcastEpisodeAccessV1: "podcastEpisodes",
  createServerListItemV1: "sharedList",
  updateServerListItemV1: "sharedList",
  deleteServerListItemV1: "sharedList",
  createServerFamilyCheckInV1: "familyCheckIns",
  deleteServerFamilyCheckInV1: "familyCheckIns",
  reserveServerFamilyMemoryV1: "familyMemories",
  finalizeServerFamilyMemoryV1: "familyMemories",
  getServerFamilyMemoryMediaAccessV1: "familyMemories",
  deleteServerFamilyMemoryV1: "familyMemories",
  setCommunityServerFollowV1: "follows",
  createServerWhiteboardStrokeV1: "whiteboard",
  undoServerWhiteboardStrokeV1: "whiteboard",
  clearServerWhiteboardV1: "whiteboard",
  reserveServerCompanyFileV1: "companyFiles",
  finalizeServerCompanyFileV1: "companyFiles",
  getServerCompanyFileAccessV1: "companyFiles",
  deleteServerCompanyFileV1: "companyFiles",
  joinServerV1: "memberships",
  createServerInviteV1: "invites",
  revokeServerInviteV1: "invites",
  respondToServerInviteV1: "memberships",
  leaveServerV1: "memberships",
  setServerMemberRoleV1: "memberships",
  removeServerMemberV1: "management",
  setServerMemberBanV1: "management",
  transferServerOwnershipV1: "memberships",
  startServerChannelSessionV1: "sessions",
  createServerChannelTokenV1: "sessions",
  endServerChannelSessionV1: "sessions",
  setServerSessionParticipantRoleV1: "participation",
  setServerSessionHandV1: "participation",
  setServerSessionMuteV1: "participation",
});

// OBS ingress extends the reviewed Servers surface without rewriting the
// frozen 54-callable table mirrored by docs/Servers.md. Keeping the extension
// explicit also makes its LiveKit-secret binding and rollout visible.
const COMMUNITY_BROADCAST_CALLABLE_METHODS = Object.freeze({
  createServerBroadcastIngressV1: "broadcast",
});
// The last-leave signal of the empty-generation grace (session_staleness.js,
// ADR-180 amendment), also kept outside the frozen documented table.
const SESSION_LIFECYCLE_CALLABLE_METHODS = Object.freeze({
  releaseServerChannelSessionIfEmptyV1: "sessions",
});
const ALL_SERVER_CALLABLE_METHODS = Object.freeze({
  ...SERVER_CALLABLE_METHODS,
  ...COMMUNITY_BROADCAST_CALLABLE_METHODS,
  ...SESSION_LIFECYCLE_CALLABLE_METHODS,
});

// Only callables that reach the media provider bind the LiveKit secrets:
// token issuance signs a JWT, session end eagerly runs one revocation page
// (sessions.js), OBS provisioning manages an RTMP ingress, and the release
// signal reads the room's occupancy (one ListParticipants).
// `startServerChannelSessionV1` validates the
// public LIVEKIT_URL only, and the three participation callables
// (session_participation.js) never touch the provider themselves: a role or
// mute change revokes through the outbox worker, which binds the secrets
// below. Binding a secret to a function that never reads it is what
// functions/media/gif/catalog.js deliberately avoids.
const SECRET_BOUND_CALLABLES = Object.freeze([
  "createServerChannelTokenV1",
  "endServerChannelSessionV1",
  "createServerBroadcastIngressV1",
  "releaseServerChannelSessionIfEmptyV1",
]);

const FAMILY_MEMORY_MEDIA_CALLABLES = Object.freeze([
  "finalizeServerFamilyMemoryV1",
  "getServerFamilyMemoryMediaAccessV1",
  "deleteServerFamilyMemoryV1",
]);

const COMPANY_FILE_MEDIA_CALLABLES = Object.freeze([
  "finalizeServerCompanyFileV1",
  "getServerCompanyFileAccessV1",
  "deleteServerCompanyFileV1",
]);

// These four endpoints can create, inspect or stop a remote Egress job. They
// need both LiveKit credentials and the dedicated service-account JSON that
// LiveKit receives to write the MP3 directly to the canonical private bucket.
const PODCAST_EGRESS_CALLABLES = Object.freeze([
  "startServerPodcastRecordingV1",
  "stopServerPodcastRecordingV1",
  "finalizeServerPodcastEpisodeV1",
  "retryServerPodcastRecordingV1",
]);

const PODCAST_EPISODE_MEDIA_CALLABLES = Object.freeze([
  "getServerPodcastEpisodeAccessV1",
]);

// These exports stay absent until the dedicated Egress credential and the
// server-side rollout switch are both ready. Podcast questions and events are
// independent and remain part of the base Podcast template.
const PODCAST_RECORDING_EXPORTS = Object.freeze([
  ...PODCAST_EGRESS_CALLABLES,
  "publishServerPodcastEpisodeV1",
  ...PODCAST_EPISODE_MEDIA_CALLABLES,
  "reconcileServerPodcastEgressSchedule",
]);

const DISPATCHER_EXPORTS = Object.freeze([
  "onServerControlOutboxCreated",
  "processPendingServerControlOutboxSchedule",
]);

// The stale-generation bound (session_staleness.js, ADR-180): not a
// dispatcher, because it does not read the outbox — it WRITES to it, through
// the same reviewed end writer every authorized lifecycle operation uses,
// and the dispatcher above then drains what it staged.
const SWEEP_EXPORTS = Object.freeze([
  "sweepStaleServerChannelSessionsSchedule",
  "sweepServerFamilyMemoryMaintenanceSchedule",
  "sweepServerCompanyFileMaintenanceSchedule",
  "reconcileServerPodcastEgressSchedule",
]);

const SERVERS_V1_EXPORT_NAMES = Object.freeze([
  ...Object.keys(ALL_SERVER_CALLABLE_METHODS),
  ...DISPATCHER_EXPORTS,
  ...SWEEP_EXPORTS,
]);

// Server channel messaging parity with direct messages (reactions, photos and
// videos). A SEPARATE extension, deliberately outside ALL_SERVER_CALLABLE_METHODS
// and SERVERS_V1_EXPORT_NAMES: the reviewed 62-total / 56-callable / 55-base
// manifest is pinned by the activation-package tool
// (tool/servers_activation_package.js) and by the registration and cold-start
// suites, and docs/Servers.md mirrors the frozen 54-entry table. These exports
// are built by createServerMessageFunctions below, behind the same runtime
// activation gate, with the same callable options and Auth binding, and are
// deployed by their own explicit selector.
// The three numbers above are 62/56/55 and not the 61/55/54 this extension was
// written against: the ADR-180 amendment landed in the same build and added
// `releaseServerChannelSessionIfEmptyV1` to the frozen manifest. Recomputed
// from the merged registration below, not relaxed — these seven exports are
// still outside it, which is why none of those numbers moved for them.
const SERVER_MESSAGE_CALLABLE_METHODS = Object.freeze({
  setServerChannelMessageReactionV1: "messageReactions",
  reserveServerChannelMessageMediaV1: "messageMedia",
  finalizeServerChannelMessageMediaV1: "messageMedia",
  getServerChannelMessageMediaAccessV1: "messageMedia",
  deleteServerChannelMessageV1: "messageMedia",
});
// The Storage-reaching callables get the Company File media profile: the
// probe reads bytes, access signs V4 URLs, delete removes the object inline.
const SERVER_MESSAGE_MEDIA_CALLABLES = Object.freeze([
  "finalizeServerChannelMessageMediaV1",
  "getServerChannelMessageMediaAccessV1",
  "deleteServerChannelMessageV1",
]);
const SERVER_MESSAGE_SCHEDULE_EXPORTS = Object.freeze([
  "expireServerChannelMessageMediaReservations",
  "processServerChannelMessageMediaDeletionJobs",
]);
const SERVER_MESSAGE_EXPORT_NAMES = Object.freeze([
  ...Object.keys(SERVER_MESSAGE_CALLABLE_METHODS),
  ...SERVER_MESSAGE_SCHEDULE_EXPORTS,
]);

// Outbox job kinds and the reviewed worker that owns each of them. The three
// workers validate their own job shape under their own transaction; this
// table only decides which of them is asked.
const CONVERGENCE_KINDS = Object.freeze([
  "memberJoined", "memberLeft", "memberRoleChanged", "sessionParticipantChanged", "channelAccess",
  "channelArchive", "channelDelete", "ownershipTransferred",
  // The management parity slice (ADR-F): a manager's removal, a ban and its
  // lift, a staff suspension and a server deletion. All five converge through
  // the same reviewed worker — a removal or ban that only edited a document
  // would leave the person connected to the room they were removed from.
  "memberRemoved", "memberBanned", "memberBanLifted", "serverModeration", "serverDelete",
]);
const OUTBOX_KINDS = Object.freeze([...CONVERGENCE_KINDS, "sessionEnd", "serverMetadata"]);

// A failure the platform may redeliver: the moment was wrong, not the job.
// Everything else — a structured refusal describing the job, a programming
// fault, a malformed document — returns normally and is retried only by the
// schedule, once per sweep, so a permanently broken job costs one worker call
// per sweep and one error line, never an Eventarc retry storm.
const TRANSIENT_CODES = Object.freeze(new Set([
  "aborted", "cancelled", "deadline-exceeded", "resource-exhausted", "unavailable", "unknown",
]));
// The same classes as gRPC status numbers, which is how the Firestore SDK
// reports an aborted or unavailable transaction.
const TRANSIENT_GRPC_CODES = Object.freeze(new Set([1, 2, 4, 8, 10, 14]));

// Fields whose change between two reads means a worker made durable progress
// on a job. Identical fingerprints after a worker call mean the job was busy,
// settled without writing, or is waiting on something the dispatcher must
// not complete on its own.
const PROGRESS_FIELDS = Object.freeze([
  "status", "grantStatus", "grantCursor", "rtcStatus", "rtcTargetIndex",
  "rtcRecipientCursor", "cursor", "lastErrorCode", "retryAfterMillis",
  "contentCleanupPending", "contentCleanupPhase", "contentCleanupStep",
  "contentCleanupChannelId", "contentCleanupChannelPhase",
  "contentCleanupRoomId", "contentCleanupRoomPhase",
]);

const DEFAULT_DISPATCH_LIMITS = Object.freeze({
  // Pages one Firestore create event may drive before yielding to the
  // schedule. Each convergence page is at most 20 recipients (four concurrent
  // provider calls); each session-end page is at most 20 SDK requests.
  triggerMaxPages: 6,
  scheduleMaxPagesPerJob: 4,
  // Pending jobs one schedule run may visit, read in pages of this size.
  scheduleScanLimit: 100,
  scheduleScanPageSize: 25,
  // No new page starts after this much wall clock, so a loop ends with a
  // written summary line and a released lease instead of a platform kill at
  // the 300 s worker timeout (a page's provider work is itself bounded).
  timeBudgetMs: 180_000,
});

// Redeclared here exactly as calls/direct_calls.js redeclares the token.js
// parameters: the params registry keeps one declaration per name, and the
// secrets are read inside a request, never at module load.
const livekitApiKey = defineSecret("LIVEKIT_API_KEY");
const livekitApiSecret = defineSecret("LIVEKIT_API_SECRET");
const livekitUrl = defineString("LIVEKIT_URL");
const LIVEKIT_SECRET_PARAMS = Object.freeze([livekitApiKey, livekitApiSecret]);

function podcastEgressSecretParams() {
  // Firebase deploy discovery treats an eager defineSecret() as required even
  // when the selected deployment omits every endpoint that binds it. Declare
  // this credential only inside the explicit Podcast-recording rollout.
  return Object.freeze([
    ...LIVEKIT_SECRET_PARAMS,
    defineSecret("PODCAST_EGRESS_GCP_CREDENTIALS"),
  ]);
}

function canonicalActivationConfig(snapshot) {
  if (!snapshot?.exists) {
    return Object.freeze({ schemaVersion: 1, callableAccess: "disabled", testerUids: [],
      workersEnabled: false, revision: 0 });
  }
  const data = snapshot.data();
  const keys = data && typeof data === "object" ? Object.keys(data).sort() : [];
  const expected = ["callableAccess", "revision", "schemaVersion", "testerUids", "workersEnabled"];
  if (!data || data.schemaVersion !== 1 || !ACTIVATION_ACCESS.includes(data.callableAccess) ||
      typeof data.workersEnabled !== "boolean" || !Number.isSafeInteger(data.revision) || data.revision < 1 ||
      !Array.isArray(data.testerUids) || data.testerUids.length > MAX_ACTIVATION_TESTERS ||
      keys.length !== expected.length || keys.some((key, index) => key !== expected[index])) {
    throw new TypeError("Malformed Servers V1 activation configuration.");
  }
  const testerUids = [];
  const seen = new Set();
  for (const uid of data.testerUids) {
    requireId(uid, "testerUid");
    if (seen.has(uid)) throw new TypeError("Duplicate Servers V1 tester uid.");
    seen.add(uid);
    testerUids.push(uid);
  }
  if (data.callableAccess !== "testers" && testerUids.length !== 0) {
    throw new TypeError("Servers V1 tester uids require tester access mode.");
  }
  return Object.freeze({ ...data, testerUids: Object.freeze(testerUids) });
}

/**
 * Runtime-only activation authority. Export discovery is intentionally static;
 * this server-owned Firestore document controls use after deployment. Missing,
 * unreadable or malformed configuration fails closed. Reads are deliberately
 * uncached so an emergency disable takes effect on the next invocation.
 */
function createServersV1ActivationGate({ db, log = logger } = {}) {
  if (typeof db?.doc !== "function") throw new TypeError("A Firestore handle is required for Servers V1 activation.");
  async function read() {
    let snapshot;
    try {
      snapshot = await db.doc(ACTIVATION_CONFIG_PATH).get();
    } catch (error) {
      log.error("servers.activation_config_unavailable", { code: safeErrorCode(error), name: error?.name ?? "Error" });
      throw new HttpsError("unavailable", "Servers are temporarily unavailable.");
    }
    try {
      return canonicalActivationConfig(snapshot);
    } catch (error) {
      log.error("servers.activation_config_invalid", { name: error?.name ?? "Error" });
      throw new HttpsError("failed-precondition", "Servers are not enabled.", {
        reason: ACTIVATION_UNAVAILABLE_REASON,
      });
    }
  }
  return Object.freeze({
    async requireCallable(uid) {
      requireId(uid, "uid");
      const config = await read();
      if (config.callableAccess === "all" ||
          (config.callableAccess === "testers" && config.testerUids.includes(uid))) return config;
      throw new HttpsError("failed-precondition", "Servers are not enabled for this account.", {
        reason: ACTIVATION_UNAVAILABLE_REASON,
      });
    },
    async workersEnabled() {
      return (await read()).workersEnabled;
    },
  });
}

function defaultRegistrars() {
  return { onCall, onDocumentCreated, onSchedule };
}

/**
 * The reviewed factories over one Firestore handle and one revocation-capable
 * LiveKit adapter. No I/O, no SDK load and no secret read happens here: the
 * adapter reads its accessors on first use, inside a request that bound them.
 */
function createServersV1Runtime({
  db = null,
  Timestamp: TimestampClass = Timestamp,
  FieldPath: FieldPathClass = FieldPath,
  clock = Date.now,
  livekit = null,
  bucket = null,
  familyMemoryStorage = null,
  familyMemoryProbe = null,
  companyFileStorage = null,
  podcastEgress = null,
  podcastEpisodeStorage = null,
  podcastEgressGcpCredentials = null,
  enablePodcastRecording = false,
} = {}) {
  if (typeof clock !== "function") throw new TypeError("clock must be a function.");
  if (typeof FieldPathClass?.documentId !== "function") throw new TypeError("FieldPath is required.");
  const database = db ?? getFirestore();
  const adapter = livekit ?? createServerLiveKitAdapter({
    apiKey: () => livekitApiKey.value(),
    apiSecret: () => livekitApiSecret.value(),
    serverUrl: () => livekitUrl.value(),
    clock,
  });
  const resolvedBucket = bucket ?? createLazyBucket(() => getStorage().bucket());
  const privateFamilyMemoryStorage = familyMemoryStorage ??
    createFamilyMemoryStorageAdapter(resolvedBucket);
  const probeFamilyMemory = familyMemoryProbe ??
    createTrustedGcsMediaProbe(resolvedBucket);
  const privateCompanyFileStorage = companyFileStorage ??
    createCompanyFileStorageAdapter(resolvedBucket);
  let podcastEpisodes = null;
  if (enablePodcastRecording === true) {
    const privatePodcastEpisodeStorage = podcastEpisodeStorage ??
      createPodcastEpisodeStorageAdapter(resolvedBucket);
    let privatePodcastEgress = podcastEgress;
    if (privatePodcastEgress === null) {
      if (typeof podcastEgressGcpCredentials !== "function") {
        throw new TypeError("Podcast Egress credentials accessor is required when recording is enabled.");
      }
      privatePodcastEgress = createLiveKitPodcastEgressAdapter({
        apiKey: () => livekitApiKey.value(),
        apiSecret: () => livekitApiSecret.value(),
        serverUrl: () => livekitUrl.value(),
        gcpCredentials: podcastEgressGcpCredentials,
        bucketName: () => resolvedBucket.name,
      });
    }
    podcastEpisodes = createServerPodcastEpisodeService({
      db: database, Timestamp: TimestampClass, FieldPath: FieldPathClass,
      livekit: adapter, clock, familyMemoryStorage: privateFamilyMemoryStorage,
      companyFileStorage: privateCompanyFileStorage,
      egress: privatePodcastEgress,
      episodeStorage: privatePodcastEpisodeStorage,
    });
  }
  const dependencies = {
    db: database, Timestamp: TimestampClass, FieldPath: FieldPathClass,
    livekit: adapter, clock, familyMemoryStorage: privateFamilyMemoryStorage,
    companyFileStorage: privateCompanyFileStorage,
  };
  return Object.freeze({
    db: database,
    FieldPath: FieldPathClass,
    clock,
    // Creation may seed an absent root active only after the registration
    // wrapper's server-owned runtime gate admits this caller. Request data can
    // never select or bypass the activation mode.
    creation: createServerCreationService({ ...dependencies, activateNewServers: true }),
    channels: createServerChannelService(dependencies),
    events: createServerEventService(dependencies),
    podcastQuestions: createServerPodcastQuestionService(dependencies),
    podcastEpisodes,
    sharedList: createServerSharedListService(dependencies),
    familyCheckIns: createServerFamilyCheckInService(dependencies),
    familyMemories: createServerFamilyMemoryService({
      ...dependencies,
      storage: privateFamilyMemoryStorage,
      probeMedia: probeFamilyMemory,
    }),
    follows: createServerFollowService(dependencies),
    whiteboard: createServerWhiteboardService(dependencies),
    companyFiles: createServerCompanyFileService({
      ...dependencies,
      storage: privateCompanyFileStorage,
    }),
    invites: createServerInviteService(dependencies),
    // Role promotions and ownership transfers announce themselves (ADR-212).
    // The notifier is injected rather than imported by the membership
    // service so a focused runtime without a default Firebase app still
    // constructs the service.
    memberships: createServerMembershipService({
      ...dependencies,
      notifyServerRolePromotion: createServerRolePromotionNotifier({
        firestore: database,
        // The same clock the rest of the runtime uses, so the notice's
        // per-actor-per-recipient budget cannot be moved by a second one.
        clock,
      }),
    }),
    management: createServerManagementService(dependencies),
    sessions: createServerSessionService(dependencies),
    broadcast: createServerCommunityBroadcastService(dependencies),
    participation: createServerSessionParticipationService(dependencies),
    projection: createServerConvergenceService(dependencies),
    convergence: createServerConvergenceRuntimeService(dependencies),
    sessionControl: createServerSessionControlService(dependencies),
    staleness: createServerSessionStalenessService(dependencies),
  });
}

/**
 * Exactly the Stage B binding (integrity/stage_b_handlers.js): keep the Auth
 * uid and token, discard every other transport property, and hand the payload
 * through unchanged. Each factory validates its exact input allowlist and
 * derives every identity from `auth.uid`, so a client-supplied ownerId,
 * memberId-as-self or forged header cannot cross this boundary.
 */
function authBoundRequest(request) {
  const auth = requireActor(request, { verified: false });
  return {
    auth: { uid: auth.uid, token: { ...(auth.token ?? {}) } },
    data: request.data,
  };
}

function safeErrorCode(error) {
  const code = error?.code;
  if (typeof code === "string" && /^[a-z0-9-]{1,64}$/u.test(code)) return code;
  if (Number.isSafeInteger(code)) return String(code);
  return "internal";
}

function callableHandler(name, method, activationGate, log) {
  return async (request) => {
    const bound = authBoundRequest(request);
    try {
      await activationGate.requireCallable(bound.auth.uid);
      return await method(bound);
    } catch (error) {
      // Factory failures are already structured HttpsErrors (integrity/guards
      // `fail`) and reach the client unchanged. Anything else is an
      // infrastructure or programming fault: log its code and class, never
      // its message (which may quote document paths), and answer `internal`.
      if (error instanceof HttpsError) throw error;
      log.error("servers.callable_failed", {
        callable: name, code: safeErrorCode(error), name: error?.name ?? "Error",
      });
      throw new HttpsError("internal", "The server operation could not be completed.");
    }
  };
}

/**
 * Read-only classification of an outbox document. `eligible` means a worker
 * invocation is worthwhile now; every other reason is a state the dispatcher
 * must leave alone: another lease holder, a retry hint that has not elapsed,
 * a finished job, or a shape no reviewed worker accepts.
 */
function describeOutboxJob(data, nowMs) {
  if (!data || typeof data !== "object" || data.schemaVersion !== 1 || !OUTBOX_KINDS.includes(data.kind)) {
    return { route: null, reason: "unsupported" };
  }
  if (data.status === "completed") return { route: null, reason: "completed" };
  if (data.status !== "pending") return { route: null, reason: "unsupported" };
  if (data.kind === "sessionEnd") {
    const leased = typeof data.leaseId === "string" && data.leaseId !== "" &&
      Number.isSafeInteger(data.leaseExpiresAtMillis) && data.leaseExpiresAtMillis > nowMs;
    return { route: "sessionEnd", reason: leased ? "leased" : "eligible" };
  }
  if (data.kind === "serverMetadata") return { route: "projection", reason: "eligible" };
  if (data.convergenceVersion !== 1) return { route: null, reason: "unsupported" };
  if (typeof data.bridgeLeaseId === "string" && data.bridgeLeaseId !== "" &&
      Number.isSafeInteger(data.bridgeLeaseExpiresAtMillis) && data.bridgeLeaseExpiresAtMillis > nowMs) {
    return { route: "convergence", reason: "leased" };
  }
  if (Number.isSafeInteger(data.retryAfterMillis) && data.retryAfterMillis > nowMs) {
    return { route: "convergence", reason: "backoff" };
  }
  return { route: "convergence", reason: "eligible" };
}

function progressFingerprint(data) {
  return JSON.stringify([
    ...PROGRESS_FIELDS.map((field) => data[field] ?? null),
    Object.hasOwn(data, "terminalDelete"),
  ]);
}

/**
 * Whether a worker's page left work behind, as a three-state answer:
 * `true` (more to do), `false` (this job is finished) and `null` (the result
 * carries no boolean signal at all). The projection worker reports completion
 * positively (`propagationComplete`); the convergence and session-end workers
 * report remaining work positively (`cleanupPending`).
 *
 * Only an explicit `false` may complete a job. A result that never stated its
 * page — a renamed field, a partial stub, a worker that returned nothing —
 * is `null` and is refused, never read as completion: inferring "done" from a
 * missing field is exactly the uncertain work this dispatcher must not settle.
 */
function workRemains(route, result) {
  const field = route === "projection" ? "propagationComplete" : "cleanupPending";
  const value = result?.[field];
  if (typeof value !== "boolean") return null;
  return field === "propagationComplete" ? !value : value;
}

function isTransientFailure(error) {
  if (error instanceof HttpsError) return TRANSIENT_CODES.has(error.code);
  return Number.isSafeInteger(error?.code) && TRANSIENT_GRPC_CODES.has(error.code);
}

/**
 * The trigger and schedule handlers. Both drive the same bounded loop: read
 * the job, stop unless it is eligible, ask its reviewed worker for one page,
 * then continue only while the worker reports remaining work AND the job
 * document visibly advanced AND it is still eligible AND the page and time
 * budgets allow. A page that ends busy, backed off or recovery-required stops
 * the loop; content cleanup advances under the same page budget and resumes
 * on the schedule. Two outcomes exist so that a
 * page is never reported as work it did not do: `busy`, when another lease
 * holder settled the job during this invocation, and `rejected` with
 * `invalid-worker-result`, when a worker returned no work-remaining boolean.
 */
function createServersV1Dispatcher({
  runtime,
  log = logger,
  random = () => randomBytes(32).toString("hex"),
  ...limits
} = {}) {
  if (!runtime?.db?.collection || typeof runtime?.FieldPath?.documentId !== "function" ||
      typeof runtime?.clock !== "function" ||
      typeof runtime?.convergence?.processServerConvergencePage !== "function" ||
      typeof runtime?.sessionControl?.processServerSessionEndPage !== "function" ||
      typeof runtime?.projection?.processServerControlOutboxPage !== "function") {
    throw new TypeError("A Servers V1 runtime with its three reviewed workers is required.");
  }
  if (typeof random !== "function") throw new TypeError("random must be a function.");
  const bounds = { ...DEFAULT_DISPATCH_LIMITS, ...limits };
  requireSafeInteger(bounds.triggerMaxPages, "triggerMaxPages", { min: 1, max: 50 });
  requireSafeInteger(bounds.scheduleMaxPagesPerJob, "scheduleMaxPagesPerJob", { min: 1, max: 50 });
  requireSafeInteger(bounds.scheduleScanLimit, "scheduleScanLimit", { min: 1, max: 1000 });
  requireSafeInteger(bounds.scheduleScanPageSize, "scheduleScanPageSize", { min: 1, max: 100 });
  requireSafeInteger(bounds.timeBudgetMs, "timeBudgetMs", { min: 1_000, max: 290_000 });
  const { db, FieldPath: FieldPathClass, clock } = runtime;
  const outbox = db.collection(OUTBOX_COLLECTION);
  const workers = Object.freeze({
    convergence: (operationId) => runtime.convergence.processServerConvergencePage({ operationId }),
    sessionEnd: (operationId) => runtime.sessionControl.processServerSessionEndPage({ operationId }),
    projection: (operationId) => runtime.projection.processServerControlOutboxPage({ operationId }),
  });

  async function dispatchOutboxJob(operationId, { source, maxPages, deadlineMs }) {
    const reference = outbox.doc(operationId);
    const report = {
      source, operationId, kind: null, outcome: null, pages: 0, processed: 0, code: null, error: null,
    };
    let previous = null;
    while (report.outcome === null) {
      const snapshot = await reference.get();
      if (!snapshot.exists) { report.outcome = "missing"; break; }
      const data = snapshot.data();
      if (OUTBOX_KINDS.includes(data?.kind)) report.kind = data.kind;
      const described = describeOutboxJob(data, clock());
      if (described.reason !== "eligible") {
        // A job that another lease holder settled between this invocation's
        // page and this read was not completed by this invocation. Crediting
        // the race with `completed` would report work this dispatcher never
        // did (and, for a session end, hide a lost lease behind a success
        // line), so the race is reported as `busy` — a deferred outcome that
        // tallies with the other deferrals and leaves the document untouched.
        report.outcome = described.reason === "completed" && report.pages > 0
          ? "busy"
          : described.reason;
        break;
      }
      const fingerprint = progressFingerprint(data);
      if (previous !== null && previous === fingerprint) { report.outcome = "stalled"; break; }
      if (report.pages >= maxPages || clock() >= deadlineMs) { report.outcome = "exhausted"; break; }
      let result;
      try {
        result = await workers[described.route](operationId);
      } catch (error) {
        report.outcome = isTransientFailure(error) ? "failed" : "rejected";
        report.code = safeErrorCode(error);
        report.error = error;
        break;
      }
      report.pages += 1;
      if (Number.isSafeInteger(result?.processed) && result.processed > 0) report.processed += result.processed;
      previous = fingerprint;
      const remaining = workRemains(described.route, result);
      if (remaining === null) {
        // Every reviewed worker states its page. A result without the boolean
        // is a contract break, not a completion: refuse the job with an error
        // line so the schedule revisits it and the break is visible.
        report.outcome = "rejected";
        report.code = "invalid-worker-result";
        break;
      }
      if (remaining === false) { report.outcome = "completed"; break; }
      if (result?.recoveryRequired === true) { report.outcome = "recoveryRequired"; break; }
    }
    return report;
  }

  function emit(report) {
    const line = {
      source: report.source, operationId: report.operationId, kind: report.kind,
      outcome: report.outcome, pages: report.pages, processed: report.processed, code: report.code,
    };
    if (report.outcome === "failed" || report.outcome === "rejected") log.error("servers.dispatch", line);
    else log.info("servers.dispatch", line);
    return line;
  }

  async function onServerControlOutboxCreated(event) {
    let operationId;
    try {
      operationId = requireId(event?.params?.operationId, "operationId");
    } catch {
      // A document id outside the operation-id grammar was not written by a
      // reviewed factory. Redelivering the event cannot change that.
      const line = { source: "trigger", operationId: null, kind: null, outcome: "unsupported", pages: 0, processed: 0, code: null };
      log.warn("servers.dispatch", line);
      return line;
    }
    // The event snapshot is not consulted: by delivery time the reviewed
    // worker may already hold a lease or have finished, so the loop reads
    // the live document instead.
    const report = await dispatchOutboxJob(operationId, {
      source: "trigger", maxPages: bounds.triggerMaxPages, deadlineMs: clock() + bounds.timeBudgetMs,
    });
    const line = emit(report);
    // Only a transient failure rethrows, so the event is redelivered with
    // backoff (`retry: true`). Rejections and every deferred outcome return
    // normally and wait for the schedule. Either way the document is exactly
    // what the reviewed worker left behind.
    if (report.outcome === "failed") throw report.error;
    return line;
  }

  function tally(counts, outcome) {
    if (outcome === "completed") counts.completed += 1;
    else if (outcome === "rejected") counts.rejected += 1;
    else if (outcome === "failed") counts.failed += 1;
    else if (outcome === "unsupported" || outcome === "missing") counts.unsupported += 1;
    else counts.deferred += 1;
  }

  async function processPendingServerControlOutbox() {
    const deadlineMs = clock() + bounds.timeBudgetMs;
    const counts = {
      scanned: 0, completed: 0, deferred: 0, rejected: 0, failed: 0, unsupported: 0, hasMore: false,
    };
    // Operation ids are uniformly distributed SHA-256 hex digests, so a random
    // start cursor with one wrap-around visits every pending job with equal
    // probability across runs. A permanently deferred prefix (recovery
    // required, content cleanup pending, a rejected job awaiting
    // reconciliation) therefore cannot starve the rest of the queue, and no
    // composite index or persisted cursor is needed: an equality filter
    // ordered by document id is served by the single-field index alone.
    const start = String(random());
    if (!/^[0-9a-f]{64}$/u.test(start)) throw new TypeError("random must return 64 hex characters.");
    let remaining = bounds.scheduleScanLimit;
    let cursor = start;
    let wrapped = false;
    scan: while (remaining > 0) {
      let query = outbox.where("status", "==", "pending").orderBy(FieldPathClass.documentId());
      if (cursor !== null) query = query.startAfter(cursor);
      const limit = Math.min(bounds.scheduleScanPageSize, remaining);
      const page = await query.limit(limit).get();
      for (const document of page.docs) {
        // After the wrap-around, ids above the start were visited already.
        if (wrapped && document.id > start) break scan;
        if (clock() >= deadlineMs) { counts.hasMore = true; break scan; }
        counts.scanned += 1;
        remaining -= 1;
        const report = await dispatchOutboxJob(document.id, {
          source: "schedule", maxPages: bounds.scheduleMaxPagesPerJob, deadlineMs,
        });
        emit(report);
        tally(counts, report.outcome);
      }
      if (page.size < limit) {
        if (wrapped) break;
        wrapped = true;
        cursor = null;
      } else {
        cursor = page.docs.at(-1).id;
        if (remaining === 0) counts.hasMore = true;
      }
    }
    log.info("servers.dispatch_sweep", counts);
    return counts;
  }

  return Object.freeze({
    describeOutboxJob,
    dispatchOutboxJob,
    onServerControlOutboxCreated,
    processPendingServerControlOutbox,
  });
}

/**
 * Builds the Servers V1 export map. Podcast recording stays excluded unless
 * its independent source-controlled rollout is explicitly enabled.
 */
function createServersV1Functions({
  runtime = null,
  registrars = defaultRegistrars(),
  enforceAppCheck = false,
  enablePodcastRecording = false,
  activationGate = null,
  log = logger,
  dispatch = {},
} = {}) {
  for (const name of ["onCall", "onDocumentCreated", "onSchedule"]) {
    if (typeof registrars?.[name] !== "function") {
      throw new TypeError(`Missing Cloud Functions registrar: ${name}.`);
    }
  }
  const podcastSecretParams = enablePodcastRecording === true
    ? podcastEgressSecretParams()
    : null;
  const resolved = runtime ?? createServersV1Runtime({
    enablePodcastRecording,
    podcastEgressGcpCredentials: podcastSecretParams === null
      ? null
      : () => podcastSecretParams.at(-1).value(),
  });
  if (typeof resolved?.staleness?.stageStaleServerChannelSessions !== "function") {
    throw new TypeError("Missing Servers V1 worker staleness.stageStaleServerChannelSessions.");
  }
  const activation = activationGate ?? createServersV1ActivationGate({ db: resolved.db, log });
  if (typeof activation?.requireCallable !== "function" || typeof activation?.workersEnabled !== "function") {
    throw new TypeError("A Servers V1 runtime activation gate is required.");
  }
  const callableOptions = {
    region: REGION,
    memory: "256MiB",
    timeoutSeconds: 60,
    maxInstances: 50,
    // Held feature: no always-on instance. test/cold_start_module_graph.test.js
    // pins the complete warm set and this surface must not join it.
    minInstances: 0,
    // Same App Check convention as Stage B and Reels: enforcement and
    // limited-use token consumption flip together, per rollout switch.
    enforceAppCheck: enforceAppCheck === true,
    consumeAppCheckToken: enforceAppCheck === true,
  };
  // One eager teardown page (at most 20 provider requests, four at a time,
  // four-second request timeouts) must fit inside the deadline.
  const securedOptions = { ...callableOptions, timeoutSeconds: 120, secrets: [...LIVEKIT_SECRET_PARAMS] };
  const mediaOptions = { ...callableOptions, memory: "512MiB", timeoutSeconds: 120 };
  const exportsMap = {};
  for (const [name, serviceName] of Object.entries(ALL_SERVER_CALLABLE_METHODS)) {
    if (enablePodcastRecording !== true && PODCAST_RECORDING_EXPORTS.includes(name)) {
      continue;
    }
    const method = resolved?.[serviceName]?.[name];
    if (typeof method !== "function") {
      throw new TypeError(`Missing Servers V1 method ${serviceName}.${name}.`);
    }
    const handler = callableHandler(name, method, activation, log);
    const options = name === "createServerBroadcastIngressV1"
      ? { ...securedOptions, maxInstances: 5 }
      : PODCAST_EGRESS_CALLABLES.includes(name)
      ? {
          ...mediaOptions,
          secrets: [...podcastSecretParams],
        }
      : SECRET_BOUND_CALLABLES.includes(name)
      ? { ...securedOptions }
      : FAMILY_MEMORY_MEDIA_CALLABLES.includes(name) ||
          COMPANY_FILE_MEDIA_CALLABLES.includes(name) ||
          PODCAST_EPISODE_MEDIA_CALLABLES.includes(name)
        ? { ...mediaOptions }
        : { ...callableOptions };
    exportsMap[name] = registrars.onCall(options, handler);
  }

  const dispatcher = createServersV1Dispatcher({ runtime: resolved, log, ...dispatch });
  async function runWorker(name, task, paused) {
    let enabled = false;
    try {
      enabled = await activation.workersEnabled();
    } catch {
      // The activation reader already emitted a non-sensitive diagnostic. A
      // trigger may return safely because the schedule will revisit any
      // durable job after configuration recovers.
    }
    if (!enabled) {
      log.info("servers.worker_paused", { worker: name });
      return paused;
    }
    return task();
  }
  const workerOptions = {
    region: REGION,
    memory: "512MiB",
    timeoutSeconds: 300,
    secrets: [...LIVEKIT_SECRET_PARAMS],
  };
  exportsMap.onServerControlOutboxCreated = registrars.onDocumentCreated(
    {
      ...workerOptions,
      document: `${OUTBOX_COLLECTION}/{operationId}`,
      // Every job is lease-guarded, so concurrent instances are safe; the
      // ceiling bounds provider concurrency, not correctness.
      maxInstances: 10,
      retry: true,
    },
    (event) => runWorker("onServerControlOutboxCreated",
      () => dispatcher.onServerControlOutboxCreated(event),
      { source: "trigger", operationId: null, kind: null, outcome: "activation-disabled", pages: 0, processed: 0, code: null }),
  );
  exportsMap.processPendingServerControlOutboxSchedule = registrars.onSchedule(
    { ...workerOptions, schedule: "every 5 minutes", timeZone: "Etc/UTC", maxInstances: 1 },
    () => runWorker("processPendingServerControlOutboxSchedule",
      () => dispatcher.processPendingServerControlOutbox(),
      { scanned: 0, completed: 0, deferred: 0, rejected: 0, failed: 0, unsupported: 0,
        hasMore: false, activationDisabled: true }),
  );
  // Same cadence as the legacy sweepStrandedLiveRoomsSchedule. A generation
  // whose emptiness was observed (release callable or provider
  // `room_finished`) ends here at most one cadence after its reconnect grace;
  // an unobserved one keeps the ADR-180 bound. maxInstances: 1 keeps two runs
  // from racing onto one generation (the staging transaction makes that
  // correct anyway, but not free).
  exportsMap.sweepStaleServerChannelSessionsSchedule = registrars.onSchedule(
    { ...workerOptions, schedule: "every 5 minutes", timeZone: "Etc/UTC", maxInstances: 1 },
    async () => runWorker("sweepStaleServerChannelSessionsSchedule", async () => {
      const outcome = await resolved.staleness.stageStaleServerChannelSessions();
      // Counts only, never ids. The last-leave and drift counters default to
      // zero so an older worker result still produces one line shape.
      const line = {
        ...outcome,
        staged: outcome.staged.length,
        stagedEmpty: outcome.stagedEmpty ?? 0,
        graceRunning: outcome.graceRunning ?? 0,
        driftRepaired: outcome.driftRepaired ?? 0,
        driftUnresolved: outcome.driftUnresolved ?? 0,
        driftTruncated: outcome.driftTruncated ?? false,
      };
      if (outcome.truncated || outcome.providerUnavailable > 0 || line.driftUnresolved > 0 || line.driftTruncated) {
        log.warn("servers.stale_session_sweep", line);
      } else log.info("servers.stale_session_sweep", line);
      return line;
    }, { scanned: 0, truncated: false, skippedLegacy: 0, skippedUnbound: 0, skippedYoung: 0,
      skippedOccupied: 0, providerUnavailable: 0, changed: 0, staged: 0, stagedEmpty: 0, graceRunning: 0,
      driftRepaired: 0, driftUnresolved: 0, driftTruncated: false, activationDisabled: true }),
  );
  exportsMap.sweepServerFamilyMemoryMaintenanceSchedule = registrars.onSchedule(
    {
      region: REGION,
      memory: "256MiB",
      timeoutSeconds: 300,
      schedule: "every 10 minutes",
      timeZone: "Etc/UTC",
      maxInstances: 1,
    },
    async () => runWorker("sweepServerFamilyMemoryMaintenanceSchedule", async () => {
      const [uploads, deletions] = await Promise.all([
        resolved.familyMemories.expireServerFamilyMemoryUploadReservations({ limit: 20 }),
        resolved.familyMemories.processPendingFamilyMemoryDeletionJobs({ limit: 20 }),
      ]);
      const line = { uploads, deletions };
      if (uploads.hasMore || deletions.hasMore) log.warn("servers.family_memory_sweep", line);
      else log.info("servers.family_memory_sweep", line);
      return line;
    }, { uploads: { processed: 0, hasMore: false, expired: [] },
      deletions: { processed: 0, hasMore: false, completed: [] }, activationDisabled: true }),
  );
  exportsMap.sweepServerCompanyFileMaintenanceSchedule = registrars.onSchedule(
    {
      region: REGION,
      memory: "512MiB",
      timeoutSeconds: 300,
      schedule: "every 10 minutes",
      timeZone: "Etc/UTC",
      maxInstances: 1,
    },
    async () => runWorker("sweepServerCompanyFileMaintenanceSchedule", async () => {
      const [uploads, deletions] = await Promise.all([
        resolved.companyFiles.expireServerCompanyFileUploadReservations({ limit: 20 }),
        resolved.companyFiles.processPendingCompanyFileDeletionJobs({ limit: 20 }),
      ]);
      const line = { uploads, deletions };
      if (uploads.hasMore || deletions.hasMore) log.warn("servers.company_file_sweep", line);
      else log.info("servers.company_file_sweep", line);
      return line;
    }, { uploads: { processed: 0, hasMore: false, expired: [] },
      deletions: { processed: 0, hasMore: false, completed: [] }, activationDisabled: true }),
  );
  if (enablePodcastRecording === true) {
    exportsMap.reconcileServerPodcastEgressSchedule = registrars.onSchedule(
      {
        region: REGION,
        memory: "512MiB",
        timeoutSeconds: 300,
        schedule: "every 5 minutes",
        timeZone: "Etc/UTC",
        maxInstances: 1,
        secrets: [...podcastSecretParams],
      },
      async () => runWorker("reconcileServerPodcastEgressSchedule", async () => {
        const line = await resolved.podcastEpisodes.reconcileServerPodcastEgressJobs({ limit: 20 });
        if (line.hasMore) log.warn("servers.podcast_egress_sweep", line);
        else log.info("servers.podcast_egress_sweep", line);
        return line;
      }, { processed: [], scanned: 0, hasMore: false, activationDisabled: true }),
    );
  }
  return Object.freeze(exportsMap);
}

/**
 * The reviewed message-parity services over one Firestore handle. Like
 * createServersV1Runtime it performs no I/O and loads no provider SDK.
 */
function createServerMessageRuntime({
  db = null,
  Timestamp: TimestampClass = Timestamp,
  clock = Date.now,
  bucket = null,
  storage = null,
  probeMedia = null,
} = {}) {
  if (typeof clock !== "function") throw new TypeError("clock must be a function.");
  const database = db ?? getFirestore();
  // Resolved on first object access, never at module load: the cold-start
  // graph pins @google-cloud/storage at zero (utils/lazy_bucket.js).
  const resolvedBucket = bucket ?? createLazyBucket(() => getStorage().bucket());
  const dependencies = { db: database, Timestamp: TimestampClass, clock };
  return Object.freeze({
    db: database,
    clock,
    messageReactions: createServerMessageReactionService(dependencies),
    messageMedia: createServerMessageMediaService({
      ...dependencies,
      storage: storage ?? createServerMessageMediaStorageAdapter(resolvedBucket),
      // The direct-message trusted probe (reels/probe.js): real image/video
      // bytes, track presence and a bounded duration from the object itself.
      probeMedia: probeMedia ?? createTrustedGcsMediaProbe(resolvedBucket),
    }),
  });
}

/**
 * Builds the message-parity export map (SERVER_MESSAGE_EXPORT_NAMES). Every
 * callable passes through the same Auth binding, the same server-owned
 * appConfig/serversV1 activation gate and the same error mapping as the base
 * Servers callables; nothing here is reachable while Servers are disabled.
 */
function createServerMessageFunctions({
  runtime = null,
  registrars = defaultRegistrars(),
  enforceAppCheck = false,
  activationGate = null,
  log = logger,
} = {}) {
  for (const name of ["onCall", "onSchedule"]) {
    if (typeof registrars?.[name] !== "function") {
      throw new TypeError(`Missing Cloud Functions registrar: ${name}.`);
    }
  }
  const resolved = runtime ?? createServerMessageRuntime();
  const activation = activationGate ?? createServersV1ActivationGate({ db: resolved.db, log });
  if (typeof activation?.requireCallable !== "function" || typeof activation?.workersEnabled !== "function") {
    throw new TypeError("A Servers V1 runtime activation gate is required.");
  }
  const callableOptions = {
    region: REGION,
    memory: "256MiB",
    timeoutSeconds: 60,
    maxInstances: 50,
    minInstances: 0,
    enforceAppCheck: enforceAppCheck === true,
    consumeAppCheckToken: enforceAppCheck === true,
  };
  const mediaOptions = { ...callableOptions, memory: "512MiB", timeoutSeconds: 120 };
  const exportsMap = {};
  for (const [name, serviceName] of Object.entries(SERVER_MESSAGE_CALLABLE_METHODS)) {
    const method = resolved?.[serviceName]?.[name];
    if (typeof method !== "function") {
      throw new TypeError(`Missing Servers V1 method ${serviceName}.${name}.`);
    }
    exportsMap[name] = registrars.onCall(
      SERVER_MESSAGE_MEDIA_CALLABLES.includes(name) ? { ...mediaOptions } : { ...callableOptions },
      callableHandler(name, method, activation, log),
    );
  }
  const media = resolved?.messageMedia;
  if (typeof media?.expireServerChannelMessageMediaReservations !== "function" ||
      typeof media?.processServerChannelMessageMediaDeletionJobs !== "function") {
    throw new TypeError("Missing Servers V1 message media workers.");
  }
  // Same gate and paused shape as the Company File sweep: workers run only
  // while appConfig/serversV1.workersEnabled is true, and durable work
  // (reservations, deletion jobs) simply waits while they are paused.
  async function runWorker(name, task, paused) {
    let enabled = false;
    try {
      enabled = await activation.workersEnabled();
    } catch {
      // The activation reader already logged a non-sensitive diagnostic.
    }
    if (!enabled) {
      log.info("servers.worker_paused", { worker: name });
      return paused;
    }
    return task();
  }
  const scheduleOptions = {
    region: REGION,
    memory: "512MiB",
    timeoutSeconds: 300,
    schedule: "every 10 minutes",
    timeZone: "Etc/UTC",
    maxInstances: 1,
  };
  exportsMap.expireServerChannelMessageMediaReservations = registrars.onSchedule(
    { ...scheduleOptions },
    async () => runWorker("expireServerChannelMessageMediaReservations", async () => {
      const line = await media.expireServerChannelMessageMediaReservations({ limit: 20 });
      if (line.hasMore) log.warn("servers.message_media_reservation_sweep", line);
      else log.info("servers.message_media_reservation_sweep", line);
      return line;
    }, { expired: [], processed: 0, hasMore: false, activationDisabled: true }),
  );
  exportsMap.processServerChannelMessageMediaDeletionJobs = registrars.onSchedule(
    { ...scheduleOptions },
    async () => runWorker("processServerChannelMessageMediaDeletionJobs", async () => {
      const line = await media.processServerChannelMessageMediaDeletionJobs({ limit: 20 });
      if (line.hasMore) log.warn("servers.message_media_deletion_sweep", line);
      else log.info("servers.message_media_deletion_sweep", line);
      return line;
    }, { completed: [], processed: 0, hasMore: false, activationDisabled: true }),
  );
  return Object.freeze(exportsMap);
}

module.exports = {
  ALL_SERVER_CALLABLE_METHODS,
  ACTIVATION_ACCESS,
  ACTIVATION_CONFIG_PATH,
  ACTIVATION_UNAVAILABLE_REASON,
  CONVERGENCE_KINDS,
  COMPANY_FILE_MEDIA_CALLABLES,
  COMMUNITY_BROADCAST_CALLABLE_METHODS,
  DEFAULT_DISPATCH_LIMITS,
  DISPATCHER_EXPORTS,
  FAMILY_MEMORY_MEDIA_CALLABLES,
  OUTBOX_COLLECTION,
  OUTBOX_KINDS,
  PODCAST_EGRESS_CALLABLES,
  PODCAST_EPISODE_MEDIA_CALLABLES,
  PODCAST_RECORDING_EXPORTS,
  REGION,
  SECRET_BOUND_CALLABLES,
  SERVER_CALLABLE_METHODS,
  SERVER_MESSAGE_CALLABLE_METHODS,
  SERVER_MESSAGE_EXPORT_NAMES,
  SERVER_MESSAGE_MEDIA_CALLABLES,
  SERVER_MESSAGE_SCHEDULE_EXPORTS,
  SERVERS_V1_EXPORT_NAMES,
  SESSION_LIFECYCLE_CALLABLE_METHODS,
  SWEEP_EXPORTS,
  authBoundRequest,
  canonicalActivationConfig,
  createServerMessageFunctions,
  createServerMessageRuntime,
  createServersV1ActivationGate,
  createServersV1Dispatcher,
  createServersV1Functions,
  createServersV1Runtime,
  describeOutboxJob,
  isTransientFailure,
};
