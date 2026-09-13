// Podcast Episodes and audio-only LiveKit Egress for Servers V1.
//
// Firestore is the lifecycle authority. Provider work is fenced by one durable
// job per episode and a short lease; a retry discovers an already-started
// egress by its canonical output path before it can dispatch another one.
// Published records contain only a first-party GCS path and generation. Every
// playback URL is short lived, generation bound and re-authorized after signing.

const {
  assertNotRestricted,
  consumeRateLimit,
  digest,
  fail,
  rateLimitReference,
  requireActor,
  requireExactInput,
  requireId,
  requireRequestId,
  requireSafeInteger,
  timestampMillis,
  transactionGetAll,
} = require("../integrity/guards");
const {
  MODERATOR_ROLES,
  denied,
  readBoundSessionAccess,
  readChannelAccess,
  validRevision,
} = require("./authority");
const { text } = require("./contract");
const { canonicalDisplayName } = require("./documents");
const { createServerOperations } = require("./operations");
const { cloudUrl } = require("./session_livekit");

const PODCAST_EPISODE_SCHEMA_VERSION = 1;
const PODCAST_AUDIO_CONTENT_TYPE = "audio/mpeg";
const PODCAST_EPISODE_ACCESS_TTL_MS = 90_000;
const PODCAST_EGRESS_LEASE_MS = 60_000;
const PODCAST_EGRESS_POLL_MS = 15_000;
const MAX_PODCAST_EPISODE_BYTES = 2 * 1024 * 1024 * 1024;
const MAX_PODCAST_EPISODE_DURATION_MS = 12 * 60 * 60_000;
const MAX_PODCAST_EPISODE_TITLE_LENGTH = 120;
const PLAYBACK_LIMIT = Object.freeze({ maxEvents: 180, windowMs: 60_000 });
const GENERATION_PATTERN = /^[0-9]{1,30}$/u;
const PROVIDER_STATUSES = Object.freeze([
  "pending",
  "starting",
  "active",
  "ending",
  "complete",
  "failed",
  "aborted",
  "limitReached",
  "unavailable",
]);
const EPISODE_STATUSES = Object.freeze([
  "recording",
  "processing",
  "ready",
  "published",
  "error",
]);

function exactObject(value, keys, label, code = "data-loss") {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(code, `${label} is malformed.`);
  }
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length ||
      actual.some((key, index) => key !== expected[index])) {
    fail(code, `${label} is malformed.`);
  }
  return value;
}

function canonicalPodcastEpisodeId(serverId, studioChannelId, sessionId) {
  requireId(serverId, "serverId");
  requireId(studioChannelId, "studioChannelId");
  requireId(sessionId, "sessionId");
  return `pe_${digest(
    "server.podcast.episode.v1",
    serverId,
    studioChannelId,
    sessionId,
  ).slice(0, 40)}`;
}

function podcastEpisodeStoragePath({ serverId, channelId, episodeId }) {
  requireId(serverId, "serverId");
  requireId(channelId, "channelId");
  requireId(episodeId, "episodeId");
  return `server_podcast_episodes/${serverId}/${channelId}/${episodeId}.mp3`;
}

function egressJobReference(db, episodeId) {
  return db.doc(`serverPodcastEgressJobs/${requireId(episodeId, "episodeId")}`);
}

function recordingStateReference(db, serverId, studioChannelId) {
  return db.doc(
    `clubs/${requireId(serverId, "serverId")}/channels/` +
    `${requireId(studioChannelId, "studioChannelId")}/podcastRecordingState/main`,
  );
}

function episodeReference(db, serverId, channelId, episodeId) {
  return db.doc(
    `clubs/${requireId(serverId, "serverId")}/channels/` +
    `${requireId(channelId, "channelId")}/episodes/${requireId(episodeId, "episodeId")}`,
  );
}

function episodeMutationInput(data, extras = []) {
  const fields = [
    "serverId",
    "channelId",
    "studioChannelId",
    "episodeId",
    "expectedRevision",
    "requestId",
    ...extras,
  ];
  requireExactInput(data, fields, fields);
  return {
    serverId: requireId(data.serverId, "serverId"),
    channelId: requireId(data.channelId, "channelId"),
    studioChannelId: requireId(data.studioChannelId, "studioChannelId"),
    episodeId: requireId(data.episodeId, "episodeId"),
    expectedRevision: requireSafeInteger(data.expectedRevision, "expectedRevision", {
      min: 1,
      max: Number.MAX_SAFE_INTEGER - 1,
    }),
    requestId: requireRequestId(data.requestId),
  };
}

function startInput(data) {
  const fields = [
    "serverId",
    "channelId",
    "studioChannelId",
    "sessionId",
    "title",
    "requestId",
  ];
  requireExactInput(data, fields, fields);
  return {
    serverId: requireId(data.serverId, "serverId"),
    channelId: requireId(data.channelId, "channelId"),
    studioChannelId: requireId(data.studioChannelId, "studioChannelId"),
    sessionId: requireId(data.sessionId, "sessionId"),
    title: text(data.title, MAX_PODCAST_EPISODE_TITLE_LENGTH, "title", 1),
    requestId: requireRequestId(data.requestId),
  };
}

function playbackInput(data) {
  const fields = ["serverId", "channelId", "episodeId"];
  requireExactInput(data, fields, fields);
  return {
    serverId: requireId(data.serverId, "serverId"),
    channelId: requireId(data.channelId, "channelId"),
    episodeId: requireId(data.episodeId, "episodeId"),
  };
}

function canonicalMedia(value, expected) {
  exactObject(
    value,
    ["storagePath", "generation", "contentType", "size", "durationMillis"],
    "The podcast episode media",
  );
  const canonicalPath = podcastEpisodeStoragePath(expected);
  if (value.storagePath !== canonicalPath ||
      typeof value.generation !== "string" ||
      !GENERATION_PATTERN.test(value.generation) ||
      value.contentType !== PODCAST_AUDIO_CONTENT_TYPE ||
      !Number.isSafeInteger(value.size) || value.size < 1 ||
      value.size > MAX_PODCAST_EPISODE_BYTES ||
      !Number.isSafeInteger(value.durationMillis) || value.durationMillis < 1 ||
      value.durationMillis > MAX_PODCAST_EPISODE_DURATION_MS) {
    fail("data-loss", "The podcast episode media needs reconciliation.");
  }
  return value;
}

function canonicalEpisode(snapshot, expected) {
  if (!snapshot?.exists) fail("not-found", "The selected podcast episode is unavailable.");
  const value = snapshot.data() ?? {};
  exactObject(value, [
    "schemaVersion",
    "episodeKind",
    "serverId",
    "clubId",
    "channelId",
    "studioChannelId",
    "episodeId",
    "sessionId",
    "livekitRoomName",
    "title",
    "status",
    "revision",
    "createdById",
    "createdByName",
    "egressId",
    "outputPath",
    "providerStatus",
    "media",
    "failureCode",
    "createdAt",
    "updatedAt",
    "stoppedAt",
    "readyAt",
    "publishedAt",
    "publishedById",
  ], "The podcast episode");
  const createdAt = timestampMillis(value.createdAt);
  const updatedAt = timestampMillis(value.updatedAt);
  const stoppedAt = value.stoppedAt === null ? null : timestampMillis(value.stoppedAt);
  const readyAt = value.readyAt === null ? null : timestampMillis(value.readyAt);
  const publishedAt = value.publishedAt === null ? null : timestampMillis(value.publishedAt);
  let canonicalId;
  let canonicalPath;
  try {
    canonicalId = canonicalPodcastEpisodeId(
      value.serverId,
      value.studioChannelId,
      value.sessionId,
    );
    canonicalPath = podcastEpisodeStoragePath(value);
    requireId(value.createdById, "createdById");
  } catch (_) {
    fail("data-loss", "The podcast episode needs reconciliation.");
  }
  const hasEgress = typeof value.egressId === "string" && value.egressId.length > 0;
  const hasMedia = value.media !== null;
  const validLifecycle =
    (value.status === "recording" &&
      ["pending", "starting", "active"].includes(value.providerStatus) &&
      (value.providerStatus === "pending" ? value.egressId === null : hasEgress) &&
      !hasMedia && value.failureCode === null && stoppedAt === null &&
      readyAt === null && publishedAt === null && value.publishedById === null) ||
    (value.status === "processing" &&
      ["ending", "complete"].includes(value.providerStatus) && hasEgress &&
      !hasMedia && value.failureCode === null && stoppedAt !== null &&
      readyAt === null && publishedAt === null && value.publishedById === null) ||
    (value.status === "ready" && value.providerStatus === "complete" && hasEgress &&
      hasMedia && value.failureCode === null && stoppedAt !== null &&
      readyAt !== null && publishedAt === null && value.publishedById === null) ||
    (value.status === "published" && value.providerStatus === "complete" && hasEgress &&
      hasMedia && value.failureCode === null && stoppedAt !== null &&
      readyAt !== null && publishedAt !== null && typeof value.publishedById === "string") ||
    (value.status === "error" &&
      ["failed", "aborted", "limitReached", "unavailable"].includes(value.providerStatus) &&
      !hasMedia && typeof value.failureCode === "string" && value.failureCode.length > 0 &&
      readyAt === null && publishedAt === null && value.publishedById === null);
  if (value.schemaVersion !== PODCAST_EPISODE_SCHEMA_VERSION ||
      value.episodeKind !== "podcastEpisode" ||
      value.serverId !== expected.serverId || value.clubId !== expected.serverId ||
      value.channelId !== expected.channelId || value.episodeId !== expected.episodeId ||
      value.episodeId !== snapshot.id || value.episodeId !== canonicalId ||
      typeof value.title !== "string" || value.title !== value.title.trim() ||
      value.title.length < 1 || value.title.length > MAX_PODCAST_EPISODE_TITLE_LENGTH ||
      !EPISODE_STATUSES.includes(value.status) ||
      !PROVIDER_STATUSES.includes(value.providerStatus) ||
      !validRevision(value.revision) ||
      typeof value.createdByName !== "string" || value.createdByName.length < 1 ||
      value.createdByName.length > 120 || value.outputPath !== canonicalPath ||
      createdAt === null || updatedAt === null || !validLifecycle) {
    fail("data-loss", "The podcast episode needs reconciliation.");
  }
  if (hasEgress) requireId(value.egressId, "egressId");
  if (hasMedia) canonicalMedia(value.media, value);
  return value;
}

function canonicalRecordingState(snapshot, expected) {
  if (!snapshot?.exists) return null;
  const value = snapshot.data() ?? {};
  exactObject(value, [
    "schemaVersion",
    "kind",
    "serverId",
    "studioChannelId",
    "channelId",
    "episodeId",
    "sessionId",
    "title",
    "status",
    "providerStatus",
    "episodeRevision",
    "updatedAt",
  ], "The podcast recording state");
  if (value.schemaVersion !== PODCAST_EPISODE_SCHEMA_VERSION ||
      value.kind !== "podcastRecordingState" || value.serverId !== expected.serverId ||
      value.studioChannelId !== expected.studioChannelId ||
      typeof value.title !== "string" || value.title.length < 1 ||
      value.title.length > MAX_PODCAST_EPISODE_TITLE_LENGTH ||
      !EPISODE_STATUSES.includes(value.status) ||
      !PROVIDER_STATUSES.includes(value.providerStatus) ||
      !validRevision(value.episodeRevision) ||
      timestampMillis(value.updatedAt) === null) {
    fail("data-loss", "The podcast recording state needs reconciliation.");
  }
  for (const key of ["channelId", "episodeId", "sessionId"]) requireId(value[key], key);
  return value;
}

function stateDocument(episode, now) {
  return {
    schemaVersion: PODCAST_EPISODE_SCHEMA_VERSION,
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

function canonicalJob(snapshot, expected = {}) {
  if (!snapshot?.exists) fail("not-found", "The podcast recording job is unavailable.");
  const value = snapshot.data() ?? {};
  exactObject(value, [
    "schemaVersion",
    "kind",
    "serverId",
    "channelId",
    "studioChannelId",
    "episodeId",
    "sessionId",
    "livekitRoomName",
    "outputPath",
    "action",
    "egressId",
    "status",
    "attemptCount",
    "nextAttemptAt",
    "leaseToken",
    "leaseExpiresAt",
    "lastErrorCode",
    "createdAt",
    "updatedAt",
  ], "The podcast recording job");
  let canonicalId;
  let canonicalPath;
  try {
    canonicalId = canonicalPodcastEpisodeId(
      value.serverId,
      value.studioChannelId,
      value.sessionId,
    );
    canonicalPath = podcastEpisodeStoragePath(value);
  } catch (_) {
    fail("data-loss", "The podcast recording job needs reconciliation.");
  }
  const leaseShape = value.leaseToken === null && value.leaseExpiresAt === null ||
    typeof value.leaseToken === "string" && value.leaseToken.length >= 8 &&
      timestampMillis(value.leaseExpiresAt) !== null;
  if (value.schemaVersion !== PODCAST_EPISODE_SCHEMA_VERSION ||
      value.kind !== "podcastEgressJob" || value.episodeId !== snapshot.id ||
      value.episodeId !== canonicalId || value.outputPath !== canonicalPath ||
      !["start", "monitor", "stop"].includes(value.action) || value.status !== "pending" ||
      !Number.isSafeInteger(value.attemptCount) || value.attemptCount < 0 ||
      value.attemptCount >= Number.MAX_SAFE_INTEGER ||
      timestampMillis(value.nextAttemptAt) === null || !leaseShape ||
      !(value.lastErrorCode === null || typeof value.lastErrorCode === "string") ||
      timestampMillis(value.createdAt) === null || timestampMillis(value.updatedAt) === null ||
      (value.action === "start" ? value.egressId !== null :
        typeof value.egressId !== "string") ||
      Object.entries(expected).some(([key, expectedValue]) => value[key] !== expectedValue)) {
    fail("data-loss", "The podcast recording job needs reconciliation.");
  }
  for (const key of [
    "serverId", "channelId", "studioChannelId", "episodeId", "sessionId",
  ]) requireId(value[key], key);
  if (value.egressId !== null) requireId(value.egressId, "egressId");
  return value;
}

function episodeReceipt(episode) {
  return {
    schemaVersion: PODCAST_EPISODE_SCHEMA_VERSION,
    serverId: episode.serverId,
    channelId: episode.channelId,
    studioChannelId: episode.studioChannelId,
    episodeId: episode.episodeId,
    sessionId: episode.sessionId,
    status: episode.status,
    revision: episode.revision,
    providerStatus: episode.providerStatus,
  };
}

function requireModerator(access) {
  if (!MODERATOR_ROLES.includes(access.member.role)) denied();
  return access;
}

function requirePodcastStudio(access) {
  if (access.server.serverType !== "podcast" || access.channel.kind !== "stage" ||
      access.channel.experience !== "broadcast" || access.channel.mediaMode !== "audio") denied();
  return access;
}

function requireEpisodesChannel(access) {
  if (access.server.serverType !== "podcast" || access.channel.kind !== "episodes") denied();
  return access;
}

function safeProviderInfo(value, expected) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("unavailable", "The recording provider returned no usable state.");
  }
  const status = value.status;
  if (!["starting", "active", "ending", "complete", "failed", "aborted", "limitReached"]
    .includes(status) || typeof value.egressId !== "string" ||
      typeof value.roomName !== "string" || value.roomName !== expected.livekitRoomName ||
      value.outputPath !== expected.outputPath) {
    fail("unavailable", "The recording provider returned an invalid binding.");
  }
  requireId(value.egressId, "egressId");
  if (expected.egressId && value.egressId !== expected.egressId) {
    fail("aborted", "The recording provider generation changed.");
  }
  if (status === "complete") {
    requireSafeInteger(value.size, "provider size", {
      min: 1,
      max: MAX_PODCAST_EPISODE_BYTES,
    });
    requireSafeInteger(value.durationMillis, "provider duration", {
      min: 1,
      max: MAX_PODCAST_EPISODE_DURATION_MS,
    });
  }
  return value;
}

function safePlaybackUrl(value) {
  if (typeof value !== "string" || value.length < 1 || value.length > 4096) return false;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && url.hostname === "storage.googleapis.com" &&
      url.username === "" && url.password === "" && url.port === "";
  } catch (_) {
    return false;
  }
}

function createPodcastEpisodeStorageAdapter(bucket) {
  if (!bucket?.file) throw new TypeError("A podcast episode Storage bucket is required.");
  return Object.freeze({
    async inspectAudio(path) {
      const [metadata] = await bucket.file(path).getMetadata();
      const generation = String(metadata?.generation ?? "");
      const size = Number(metadata?.size);
      if (!GENERATION_PATTERN.test(generation) || !Number.isSafeInteger(size) || size < 1 ||
          size > MAX_PODCAST_EPISODE_BYTES || metadata?.contentType !== PODCAST_AUDIO_CONTENT_TYPE) {
        fail("failed-precondition", "The recorded podcast audio is invalid.");
      }
      const custom = metadata?.metadata && typeof metadata.metadata === "object"
        ? metadata.metadata
        : {};
      if (typeof custom.firebaseStorageDownloadTokens === "string" &&
          custom.firebaseStorageDownloadTokens.length > 0) {
        await bucket.file(path).setMetadata({
          metadata: { ...custom, firebaseStorageDownloadTokens: null },
        }, { ifGenerationMatch: generation });
      }
      return {
        storagePath: path,
        generation,
        contentType: PODCAST_AUDIO_CONTENT_TYPE,
        size,
      };
    },
    async getSignedReadUrl(path, { generation, expiresAtMs }) {
      if (!GENERATION_PATTERN.test(generation) || !Number.isSafeInteger(expiresAtMs) ||
          expiresAtMs <= 0) fail("failed-precondition", "The episode access grant is malformed.");
      const [url] = await bucket.file(path).getSignedUrl({
        version: "v4",
        action: "read",
        expires: expiresAtMs,
        queryParams: { generation },
      });
      return url;
    },
    async deleteUnpublished(path, { generation = null } = {}) {
      if (generation !== null && !GENERATION_PATTERN.test(generation)) {
        fail("failed-precondition", "The podcast episode deletion fence is malformed.");
      }
      await bucket.file(path).delete({
        ignoreNotFound: true,
        ...(generation === null ? {} : { ifGenerationMatch: generation }),
      });
    },
  });
}

function bigIntMillis(value) {
  let raw;
  try { raw = BigInt(value ?? 0); } catch { return null; }
  if (raw <= 0n) return null;
  const millis = Number(raw / 1_000_000n);
  return Number.isSafeInteger(millis) && millis > 0 ? millis : null;
}

function providerStatus(value, statuses) {
  const map = new Map([
    [statuses.EGRESS_STARTING ?? 0, "starting"],
    [statuses.EGRESS_ACTIVE ?? 1, "active"],
    [statuses.EGRESS_ENDING ?? 2, "ending"],
    [statuses.EGRESS_COMPLETE ?? 3, "complete"],
    [statuses.EGRESS_FAILED ?? 4, "failed"],
    [statuses.EGRESS_ABORTED ?? 5, "aborted"],
    [statuses.EGRESS_LIMIT_REACHED ?? 6, "limitReached"],
  ]);
  return map.get(value) ?? null;
}

function outputPathOf(info) {
  const request = info?.request?.value;
  const candidates = [
    request?.fileOutputs?.[0]?.filepath,
    request?.output?.case === "file" ? request.output.value?.filepath : null,
    info?.fileResults?.[0]?.filename,
    info?.result?.case === "file" ? info.result.value?.filename : null,
  ];
  return candidates.find((value) => typeof value === "string" && value.length > 0) ?? null;
}

function createLiveKitPodcastEgressAdapter({
  apiKey,
  apiSecret,
  serverUrl,
  gcpCredentials,
  bucketName,
  client = null,
  loadSdk = () => require("livekit-server-sdk"),
}) {
  if (![apiKey, apiSecret, serverUrl, gcpCredentials, bucketName]
    .every((value) => typeof value === "function")) {
    throw new TypeError("Explicit podcast Egress configuration accessors are required.");
  }
  let transport = client;
  function configuration() {
    const key = apiKey();
    const secret = apiSecret();
    const websocketUrl = cloudUrl(serverUrl());
    const credentials = gcpCredentials();
    const bucket = bucketName();
    let parsed;
    try { parsed = JSON.parse(credentials); } catch (_) {
      fail("failed-precondition", "Podcast recording Storage is not configured.");
    }
    if (typeof key !== "string" || !key || typeof secret !== "string" || !secret ||
        typeof credentials !== "string" || !credentials ||
        parsed?.type !== "service_account" || typeof parsed.client_email !== "string" ||
        typeof parsed.private_key !== "string" || typeof bucket !== "string" ||
        !/^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$/u.test(bucket)) {
      fail("failed-precondition", "Podcast recording Storage is not configured.");
    }
    return {
      key,
      secret,
      credentials,
      bucket,
      endpoint: websocketUrl.replace(/^wss:/u, "https:"),
    };
  }
  function sdkAndClient() {
    const config = configuration();
    const sdk = loadSdk();
    if (!transport) {
      transport = new sdk.EgressClient(config.endpoint, config.key, config.secret, {
        requestTimeout: 10,
        failover: false,
      });
    }
    return { sdk, transport, config };
  }
  function normalize(info, expectedPath) {
    const { sdk } = sdkAndClient();
    const status = providerStatus(info?.status, sdk.EgressStatus);
    const outputPath = outputPathOf(info);
    if (!status || typeof info?.egressId !== "string" ||
        typeof info?.roomName !== "string" || outputPath !== expectedPath) {
      fail("unavailable", "The recording provider returned an invalid binding.");
    }
    const file = info.fileResults?.find((item) => item.filename === expectedPath) ??
      (info.result?.case === "file" && info.result.value?.filename === expectedPath
        ? info.result.value
        : null);
    return {
      egressId: info.egressId,
      roomName: info.roomName,
      status,
      outputPath,
      ...(status === "complete"
        ? {
            size: Number(file?.size ?? 0),
            durationMillis: bigIntMillis(file?.duration),
          }
        : {}),
    };
  }
  return Object.freeze({
    assertSupported: configuration,
    async ensureAudioRecording({ roomName, outputPath }) {
      const { sdk, transport: egress, config } = sdkAndClient();
      const existing = await egress.listEgress({ roomName });
      const found = existing.find((item) => {
        const status = providerStatus(item?.status, sdk.EgressStatus);
        return outputPathOf(item) === outputPath &&
          !["failed", "aborted", "limitReached"].includes(status);
      });
      if (found) return normalize(found, outputPath);
      const output = new sdk.EncodedFileOutput({
        fileType: sdk.EncodedFileType.MP3,
        filepath: outputPath,
        disableManifest: true,
        output: {
          case: "gcp",
          value: new sdk.GCPUpload({
            credentials: config.credentials,
            bucket: config.bucket,
          }),
        },
      });
      return normalize(await egress.startRoomCompositeEgress(
        roomName,
        { file: output },
        { audioOnly: true, videoOnly: false },
      ), outputPath);
    },
    async getRecording(egressId, outputPath) {
      const { transport: egress } = sdkAndClient();
      const matches = await egress.listEgress({ egressId });
      if (matches.length !== 1) {
        fail("unavailable", "The recording provider generation is unavailable.");
      }
      return normalize(matches[0], outputPath);
    },
    async stopRecording(egressId, outputPath) {
      const { transport: egress } = sdkAndClient();
      return normalize(await egress.stopEgress(egressId), outputPath);
    },
  });
}

function createServerPodcastEpisodeService(dependencies) {
  const {
    db,
    Timestamp,
    egress,
    episodeStorage,
    clock = Date.now,
    randomId = () => require("node:crypto").randomUUID(),
  } = dependencies;
  if (!db?.runTransaction || !Timestamp?.fromMillis || typeof clock !== "function" ||
      typeof randomId !== "function" || !egress?.assertSupported ||
      !egress?.ensureAudioRecording || !egress?.getRecording || !egress?.stopRecording ||
      !episodeStorage?.inspectAudio || !episodeStorage?.getSignedReadUrl ||
      !episodeStorage?.deleteUnpublished) {
    throw new TypeError(
      "db, Timestamp, Egress, podcast Storage, clock and randomId are required.",
    );
  }
  const operations = createServerOperations(dependencies);

  async function channelPair(transaction, uid, input, capability = "read") {
    const studio = requirePodcastStudio(await readChannelAccess({
      db,
      transaction,
      uid,
      serverId: input.serverId,
      channelId: input.studioChannelId,
      capability,
    }));
    const episodes = requireEpisodesChannel(await readChannelAccess({
      db,
      transaction,
      uid,
      serverId: input.serverId,
      channelId: input.channelId,
      capability,
      serverAccess: studio,
    }));
    return { studio, episodes };
  }

  async function currentEpisodeReceipt(input) {
    const snapshot = await episodeReference(
      db,
      input.serverId,
      input.channelId,
      input.episodeId,
    ).get();
    return episodeReceipt(canonicalEpisode(snapshot, input));
  }

  function freshJob(episode, now, { action, egressId = null }) {
    return {
      schemaVersion: PODCAST_EPISODE_SCHEMA_VERSION,
      kind: "podcastEgressJob",
      serverId: episode.serverId,
      channelId: episode.channelId,
      studioChannelId: episode.studioChannelId,
      episodeId: episode.episodeId,
      sessionId: episode.sessionId,
      livekitRoomName: episode.livekitRoomName,
      outputPath: episode.outputPath,
      action,
      egressId,
      status: "pending",
      attemptCount: 0,
      nextAttemptAt: now,
      leaseToken: null,
      leaseExpiresAt: null,
      lastErrorCode: null,
      createdAt: now,
      updatedAt: now,
    };
  }

  async function claimJob(episodeId, { force = false } = {}) {
    const nowMs = clock();
    const now = Timestamp.fromMillis(nowMs);
    const token = requireRequestId(String(randomId()).replace(/[^A-Za-z0-9_-]/gu, "_"));
    return db.runTransaction(async (transaction) => {
      const reference = egressJobReference(db, episodeId);
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) return null;
      const job = canonicalJob(snapshot);
      const nextAttemptAt = timestampMillis(job.nextAttemptAt);
      const leaseExpiresAt = job.leaseExpiresAt === null
        ? null
        : timestampMillis(job.leaseExpiresAt);
      if (leaseExpiresAt !== null && leaseExpiresAt > nowMs) return null;
      if (!force && nextAttemptAt > nowMs) return null;
      transaction.update(reference, {
        leaseToken: token,
        leaseExpiresAt: Timestamp.fromMillis(nowMs + PODCAST_EGRESS_LEASE_MS),
        updatedAt: now,
      });
      return { ...job, leaseToken: token };
    });
  }

  async function releaseJob(job, { errorCode = null, delayMs = PODCAST_EGRESS_POLL_MS } = {}) {
    const nowMs = clock();
    const now = Timestamp.fromMillis(nowMs);
    await db.runTransaction(async (transaction) => {
      const reference = egressJobReference(db, job.episodeId);
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) return;
      const current = canonicalJob(snapshot, { episodeId: job.episodeId });
      if (current.leaseToken !== job.leaseToken) return;
      transaction.update(reference, {
        attemptCount: current.attemptCount + 1,
        nextAttemptAt: Timestamp.fromMillis(nowMs + delayMs),
        leaseToken: null,
        leaseExpiresAt: null,
        lastErrorCode: errorCode,
        updatedAt: now,
      });
    });
  }

  async function markProviderError(job, info) {
    const now = Timestamp.fromMillis(clock());
    await db.runTransaction(async (transaction) => {
      const jobRef = egressJobReference(db, job.episodeId);
      const episodeRef = episodeReference(db, job.serverId, job.channelId, job.episodeId);
      const stateRef = recordingStateReference(db, job.serverId, job.studioChannelId);
      const [jobSnapshot, episodeSnapshot, stateSnapshot] = await transactionGetAll(
        transaction,
        jobRef,
        episodeRef,
        stateRef,
      );
      const currentJob = canonicalJob(jobSnapshot, { episodeId: job.episodeId });
      if (currentJob.leaseToken !== job.leaseToken) return;
      const episode = canonicalEpisode(episodeSnapshot, job);
      const state = canonicalRecordingState(stateSnapshot, job);
      if (!state || state.episodeId !== episode.episodeId ||
          state.episodeRevision !== episode.revision) {
        fail("data-loss", "The podcast recording state changed during provider failure.");
      }
      const revision = episode.revision + 1;
      if (!validRevision(revision)) fail("data-loss", "The podcast episode revision is exhausted.");
      const failureCode = `provider-${info.status}`;
      transaction.update(episodeRef, {
        status: "error",
        revision,
        egressId: info.egressId ?? episode.egressId,
        providerStatus: info.status,
        failureCode,
        updatedAt: now,
      });
      transaction.set(stateRef, stateDocument({ ...episode,
        status: "error", revision, providerStatus: info.status }, now));
      transaction.delete(jobRef);
    });
  }

  async function completeEpisode(job, info) {
    const provider = safeProviderInfo(info, job);
    const inspected = await episodeStorage.inspectAudio(job.outputPath);
    if (inspected.storagePath !== job.outputPath || inspected.size !== provider.size ||
        inspected.contentType !== PODCAST_AUDIO_CONTENT_TYPE ||
        typeof inspected.generation !== "string" ||
        !GENERATION_PATTERN.test(inspected.generation)) {
      fail("failed-precondition", "The recorded podcast audio does not match its provider result.");
    }
    const media = {
      ...inspected,
      durationMillis: provider.durationMillis,
    };
    const now = Timestamp.fromMillis(clock());
    await db.runTransaction(async (transaction) => {
      const jobRef = egressJobReference(db, job.episodeId);
      const episodeRef = episodeReference(db, job.serverId, job.channelId, job.episodeId);
      const stateRef = recordingStateReference(db, job.serverId, job.studioChannelId);
      const [jobSnapshot, episodeSnapshot, stateSnapshot] = await transactionGetAll(
        transaction,
        jobRef,
        episodeRef,
        stateRef,
      );
      const currentJob = canonicalJob(jobSnapshot, { episodeId: job.episodeId });
      if (currentJob.leaseToken !== job.leaseToken || currentJob.egressId !== provider.egressId) {
        return;
      }
      const episode = canonicalEpisode(episodeSnapshot, job);
      const state = canonicalRecordingState(stateSnapshot, job);
      if (episode.egressId !== provider.egressId ||
          !["recording", "processing"].includes(episode.status) ||
          !state || state.episodeId !== episode.episodeId ||
          state.episodeRevision !== episode.revision) {
        fail("data-loss", "The podcast episode changed during finalization.");
      }
      const revision = episode.revision + 1;
      if (!validRevision(revision)) fail("data-loss", "The podcast episode revision is exhausted.");
      const stoppedAt = episode.stoppedAt ?? now;
      transaction.update(episodeRef, {
        status: "ready",
        revision,
        providerStatus: "complete",
        media,
        stoppedAt,
        readyAt: now,
        failureCode: null,
        updatedAt: now,
      });
      transaction.set(stateRef, stateDocument({
        ...episode,
        status: "ready",
        revision,
        providerStatus: "complete",
      }, now));
      transaction.delete(jobRef);
    });
  }

  async function applyProviderInfo(job, raw) {
    const info = safeProviderInfo(raw, job);
    if (["failed", "aborted", "limitReached"].includes(info.status)) {
      await markProviderError(job, info);
      return;
    }
    if (info.status === "complete") {
      await completeEpisode(job, info);
      return;
    }
    const nowMs = clock();
    const now = Timestamp.fromMillis(nowMs);
    await db.runTransaction(async (transaction) => {
      const jobRef = egressJobReference(db, job.episodeId);
      const episodeRef = episodeReference(db, job.serverId, job.channelId, job.episodeId);
      const stateRef = recordingStateReference(db, job.serverId, job.studioChannelId);
      const [jobSnapshot, episodeSnapshot, stateSnapshot] = await transactionGetAll(
        transaction,
        jobRef,
        episodeRef,
        stateRef,
      );
      const currentJob = canonicalJob(jobSnapshot, { episodeId: job.episodeId });
      if (currentJob.leaseToken !== job.leaseToken) return;
      const episode = canonicalEpisode(episodeSnapshot, job);
      const state = canonicalRecordingState(stateSnapshot, job);
      if (!state || state.episodeId !== episode.episodeId ||
          state.episodeRevision !== episode.revision) {
        fail("data-loss", "The podcast recording state changed during reconciliation.");
      }
      const processing = episode.status === "processing" ||
        info.status === "ending" || currentJob.action === "stop";
      const status = processing ? "processing" : "recording";
      const storedProviderStatus = processing ? "ending" : info.status;
      const revision = episode.status === status && episode.egressId === info.egressId &&
        episode.providerStatus === storedProviderStatus
        ? episode.revision
        : episode.revision + 1;
      if (!validRevision(revision)) fail("data-loss", "The podcast episode revision is exhausted.");
      transaction.update(episodeRef, {
        status,
        revision,
        egressId: info.egressId,
        providerStatus: storedProviderStatus,
        stoppedAt: processing ? episode.stoppedAt ?? now : null,
        failureCode: null,
        updatedAt: now,
      });
      transaction.set(stateRef, stateDocument({
        ...episode,
        status,
        revision,
        providerStatus: storedProviderStatus,
      }, now));
      transaction.update(jobRef, {
        action: processing && ["starting", "active"].includes(info.status)
          ? "stop"
          : "monitor",
        egressId: info.egressId,
        attemptCount: currentJob.attemptCount + 1,
        nextAttemptAt: Timestamp.fromMillis(nowMs + PODCAST_EGRESS_POLL_MS),
        leaseToken: null,
        leaseExpiresAt: null,
        lastErrorCode: null,
        updatedAt: now,
      });
    });
  }

  async function processPodcastEgressJob(episodeId, { force = false } = {}) {
    const job = await claimJob(episodeId, { force });
    if (!job) return { processed: false };
    try {
      let info;
      if (job.action === "start") {
        info = await egress.ensureAudioRecording({
          roomName: job.livekitRoomName,
          outputPath: job.outputPath,
          operationId: job.episodeId,
        });
      } else {
        info = await egress.getRecording(job.egressId, job.outputPath);
        if (job.action === "stop" && ["starting", "active"].includes(info.status)) {
          info = await egress.stopRecording(job.egressId, job.outputPath);
        }
      }
      await applyProviderInfo(job, info);
      return { processed: true, episodeId: job.episodeId };
    } catch (error) {
      await releaseJob(job, { errorCode: "provider-unavailable" });
      throw error;
    }
  }

  async function startServerPodcastRecordingV1(request) {
    const input = startInput(request.data);
    egress.assertSupported();
    const episodeId = canonicalPodcastEpisodeId(
      input.serverId,
      input.studioChannelId,
      input.sessionId,
    );
    const staged = await operations.execute(
      request,
      "server.podcast.recording.start.v1",
      input,
      async ({ transaction, auth, prior, now }) => {
        const studio = requireModerator(requirePodcastStudio(await readBoundSessionAccess({
          db,
          transaction,
          uid: auth.uid,
          serverId: input.serverId,
          channelId: input.studioChannelId,
          sessionId: input.sessionId,
          capability: "joinVoice",
        })));
        const episodes = requireEpisodesChannel(await readChannelAccess({
          db,
          transaction,
          uid: auth.uid,
          serverId: input.serverId,
          channelId: input.channelId,
          capability: "write",
          serverAccess: studio,
        }));
        const episodeRef = episodes.channelReference.collection("episodes").doc(episodeId);
        const stateRef = recordingStateReference(db, input.serverId, input.studioChannelId);
        const jobRef = egressJobReference(db, episodeId);
        const [episodeSnapshot, stateSnapshot, jobSnapshot] = await transactionGetAll(
          transaction,
          episodeRef,
          stateRef,
          jobRef,
        );
        if (prior) {
          const episode = canonicalEpisode(episodeSnapshot, { ...input, episodeId });
          if (episode.createdById !== auth.uid || episode.title !== input.title) {
            fail("aborted", "The podcast episode changed after the original request.");
          }
          return prior;
        }
        if (episodeSnapshot.exists || jobSnapshot.exists) {
          fail("data-loss", "A podcast recording exists without its creation receipt.");
        }
        const currentState = canonicalRecordingState(stateSnapshot, input);
        if (currentState && ["recording", "processing"].includes(currentState.status)) {
          fail("failed-precondition", "Finish the current podcast recording first.");
        }
        const outputPath = podcastEpisodeStoragePath({
          serverId: input.serverId,
          channelId: input.channelId,
          episodeId,
        });
        const episode = {
          schemaVersion: PODCAST_EPISODE_SCHEMA_VERSION,
          episodeKind: "podcastEpisode",
          serverId: input.serverId,
          clubId: input.serverId,
          channelId: input.channelId,
          studioChannelId: input.studioChannelId,
          episodeId,
          sessionId: input.sessionId,
          livekitRoomName: studio.livekitRoomName,
          title: input.title,
          status: "recording",
          revision: 1,
          createdById: auth.uid,
          createdByName: canonicalDisplayName(studio.profile),
          egressId: null,
          outputPath,
          providerStatus: "pending",
          media: null,
          failureCode: null,
          createdAt: now,
          updatedAt: now,
          stoppedAt: null,
          readyAt: null,
          publishedAt: null,
          publishedById: null,
        };
        transaction.create(episodeRef, episode);
        transaction.set(stateRef, stateDocument(episode, now));
        transaction.create(jobRef, freshJob(episode, now, { action: "start" }));
        return episodeReceipt(episode);
      },
    );
    try {
      await processPodcastEgressJob(episodeId, { force: true });
    } catch (_) {
      fail("unavailable", "Podcast recording is queued but the provider is unavailable. Retry.");
    }
    return currentEpisodeReceipt({ ...input, episodeId }).catch(() => staged);
  }

  async function stopServerPodcastRecordingV1(request) {
    const input = episodeMutationInput(request.data);
    const staged = await operations.execute(
      request,
      "server.podcast.recording.stop.v1",
      input,
      async ({ transaction, auth, prior, now }) => {
        const pair = await channelPair(transaction, auth.uid, input, "write");
        requireModerator(pair.studio);
        const episodeRef = pair.episodes.channelReference.collection("episodes").doc(input.episodeId);
        const stateRef = recordingStateReference(db, input.serverId, input.studioChannelId);
        const jobRef = egressJobReference(db, input.episodeId);
        const [episodeSnapshot, stateSnapshot, jobSnapshot] = await transactionGetAll(
          transaction,
          episodeRef,
          stateRef,
          jobRef,
        );
        const episode = canonicalEpisode(episodeSnapshot, input);
        const state = canonicalRecordingState(stateSnapshot, input);
        if (prior) {
          if (episode.sessionId !== prior.sessionId || episode.egressId !== prior.egressId) {
            fail("aborted", "The podcast recording changed after the stop request.");
          }
          return prior;
        }
        if (episode.revision !== input.expectedRevision) {
          fail("aborted", "The podcast episode changed. Refresh before stopping it.");
        }
        if (episode.status !== "recording" || episode.egressId === null ||
            !state || state.episodeId !== episode.episodeId ||
            state.episodeRevision !== episode.revision) {
          fail("failed-precondition", "This podcast episode is not recording.");
        }
        const job = canonicalJob(jobSnapshot, { episodeId: input.episodeId });
        if (job.egressId !== episode.egressId || !["monitor", "start"].includes(job.action)) {
          fail("data-loss", "The podcast recording stop fence is unavailable.");
        }
        const revision = episode.revision + 1;
        if (!validRevision(revision)) fail("data-loss", "The podcast episode revision is exhausted.");
        transaction.update(episodeRef, {
          status: "processing",
          revision,
          providerStatus: "ending",
          stoppedAt: now,
          updatedAt: now,
        });
        transaction.set(stateRef, stateDocument({ ...episode,
          status: "processing", revision, providerStatus: "ending" }, now));
        transaction.update(jobRef, {
          action: "stop",
          egressId: episode.egressId,
          nextAttemptAt: now,
          leaseToken: null,
          leaseExpiresAt: null,
          lastErrorCode: null,
          updatedAt: now,
        });
        return {
          ...episodeReceipt({ ...episode, status: "processing", revision }),
          egressId: episode.egressId,
        };
      },
    );
    try { await processPodcastEgressJob(input.episodeId, { force: true }); } catch (_) {
      // The durable stop job is retried by finalize/scheduled reconciliation.
    }
    return staged;
  }

  async function finalizeServerPodcastEpisodeV1(request) {
    const input = episodeMutationInput(request.data);
    const acknowledged = await operations.execute(
      request,
      "server.podcast.episode.finalize.v1",
      input,
      async ({ transaction, auth, prior }) => {
        const pair = await channelPair(transaction, auth.uid, input, "write");
        requireModerator(pair.studio);
        const snapshot = await transaction.get(
          pair.episodes.channelReference.collection("episodes").doc(input.episodeId),
        );
        const episode = canonicalEpisode(snapshot, input);
        if (prior) return prior;
        if (episode.revision !== input.expectedRevision) {
          fail("aborted", "The podcast episode changed. Refresh before finalizing it.");
        }
        if (!["recording", "processing"].includes(episode.status) ||
            episode.egressId === null) {
          fail("failed-precondition", "This podcast episode is not awaiting finalization.");
        }
        return episodeReceipt(episode);
      },
    );
    try {
      await processPodcastEgressJob(input.episodeId, { force: true });
    } catch (_) {
      fail("unavailable", "The podcast episode is still processing. Retry shortly.");
    }
    return currentEpisodeReceipt(input).catch(() => acknowledged);
  }

  async function retryServerPodcastRecordingV1(request) {
    const input = episodeMutationInput(request.data);
    egress.assertSupported();
    const staged = await operations.execute(
      request,
      "server.podcast.recording.retry.v1",
      input,
      async ({ transaction, auth, prior, now }) => {
        const pair = await channelPair(transaction, auth.uid, input, "write");
        requireModerator(pair.studio);
        const episodeRef = pair.episodes.channelReference.collection("episodes")
          .doc(input.episodeId);
        const stateRef = recordingStateReference(db, input.serverId, input.studioChannelId);
        const jobRef = egressJobReference(db, input.episodeId);
        const [episodeSnapshot, stateSnapshot, jobSnapshot] = await transactionGetAll(
          transaction,
          episodeRef,
          stateRef,
          jobRef,
        );
        const episode = canonicalEpisode(episodeSnapshot, input);
        const state = canonicalRecordingState(stateSnapshot, input);
        if (prior) {
          // The durable provider worker may advance the staged `pending`
          // receipt to `starting`/`active` before the first callable returns.
          // A replay therefore accepts the same still-recording generation at
          // a later revision, then lets the outer provider reconciliation
          // return the current receipt. It must never turn a completed,
          // published or otherwise changed lifecycle back into a retry.
          if (episode.status === "recording" &&
              episode.sessionId === prior.sessionId &&
              episode.revision >= prior.revision &&
              state?.episodeId === episode.episodeId &&
              state.episodeRevision === episode.revision &&
              jobSnapshot.exists) {
            return prior;
          }
          fail("aborted", "The podcast recording changed after the retry request.");
        }
        if (episode.revision !== input.expectedRevision) {
          fail("aborted", "The podcast episode changed. Refresh before retrying it.");
        }
        if (episode.status !== "error" || episode.media !== null || jobSnapshot.exists ||
            !state || state.episodeId !== episode.episodeId ||
            state.episodeRevision !== episode.revision) {
          fail("failed-precondition", "This podcast recording cannot be retried.");
        }
        const live = requireModerator(requirePodcastStudio(await readBoundSessionAccess({
          db,
          transaction,
          uid: auth.uid,
          serverId: input.serverId,
          channelId: input.studioChannelId,
          sessionId: episode.sessionId,
          capability: "joinVoice",
        })));
        if (live.livekitRoomName !== episode.livekitRoomName) {
          fail("failed-precondition", "The podcast media generation changed.");
        }
        const revision = episode.revision + 1;
        if (!validRevision(revision)) fail("data-loss", "The podcast episode revision is exhausted.");
        const recording = {
          ...episode,
          status: "recording",
          revision,
          egressId: null,
          providerStatus: "pending",
          failureCode: null,
          stoppedAt: null,
          updatedAt: now,
        };
        transaction.update(episodeRef, {
          status: recording.status,
          revision,
          egressId: null,
          providerStatus: recording.providerStatus,
          failureCode: null,
          stoppedAt: null,
          updatedAt: now,
        });
        transaction.set(stateRef, stateDocument(recording, now));
        transaction.create(jobRef, freshJob(recording, now, { action: "start" }));
        return episodeReceipt(recording);
      },
    );
    try {
      await processPodcastEgressJob(input.episodeId, { force: true });
    } catch (_) {
      fail("unavailable", "Podcast recording retry is queued. Try again shortly.");
    }
    return currentEpisodeReceipt(input).catch(() => staged);
  }

  async function publishServerPodcastEpisodeV1(request) {
    const input = episodeMutationInput(request.data);
    return operations.execute(
      request,
      "server.podcast.episode.publish.v1",
      input,
      async ({ transaction, auth, prior, now }) => {
        const pair = await channelPair(transaction, auth.uid, input, "write");
        requireModerator(pair.studio);
        const reference = pair.episodes.channelReference.collection("episodes").doc(input.episodeId);
        const stateRef = recordingStateReference(db, input.serverId, input.studioChannelId);
        const [snapshot, stateSnapshot] = await transactionGetAll(
          transaction,
          reference,
          stateRef,
        );
        const episode = canonicalEpisode(snapshot, input);
        if (prior) {
          if (episode.status === "published" && episode.revision === prior.revision) return prior;
          fail("aborted", "The podcast episode changed after publication.");
        }
        if (episode.revision !== input.expectedRevision) {
          fail("aborted", "The podcast episode changed. Refresh before publishing it.");
        }
        if (episode.status !== "ready") {
          fail("failed-precondition", "Only a ready podcast episode can be published.");
        }
        const revision = episode.revision + 1;
        if (!validRevision(revision)) fail("data-loss", "The podcast episode revision is exhausted.");
        const state = canonicalRecordingState(stateSnapshot, input);
        transaction.update(reference, {
          status: "published",
          revision,
          publishedAt: now,
          publishedById: auth.uid,
          updatedAt: now,
        });
        if (state?.episodeId === episode.episodeId && state.episodeRevision === episode.revision) {
          transaction.set(stateRef, stateDocument({ ...episode,
            status: "published", revision }, now));
        }
        return episodeReceipt({ ...episode, status: "published", revision });
      },
    );
  }

  async function authorizePlayback(auth, input, { consume = false } = {}) {
    const nowMs = clock();
    const now = Timestamp.fromMillis(nowMs);
    return db.runTransaction(async (transaction) => {
      const access = requireEpisodesChannel(await readChannelAccess({
        db,
        transaction,
        uid: auth.uid,
        serverId: input.serverId,
        channelId: input.channelId,
        capability: "read",
      }));
      const episodeRef = access.channelReference.collection("episodes").doc(input.episodeId);
      const restrictionRef = db.doc(`restrictions/${auth.uid}`);
      const rateRef = rateLimitReference(db, "server.podcast.episode.access", auth.uid);
      const snapshots = consume
        ? await transactionGetAll(transaction, episodeRef, restrictionRef, rateRef)
        : await transactionGetAll(transaction, episodeRef, restrictionRef);
      assertNotRestricted(snapshots[1], "Your", nowMs);
      const episode = canonicalEpisode(snapshots[0], input);
      if (episode.status !== "published" && !MODERATOR_ROLES.includes(access.member.role)) denied();
      if (!["ready", "published"].includes(episode.status)) denied();
      if (consume) {
        consumeRateLimit(transaction, snapshots[2], {
          reference: rateRef,
          scope: "server.podcast.episode.access",
          uid: auth.uid,
          now,
          nowMs,
          ...PLAYBACK_LIMIT,
        });
      }
      return {
        checkedAtMs: nowMs,
        serverRevision: access.server.revision,
        channelRevision: access.channel.revision,
        channelAclRevision: access.channel.aclRevision,
        membershipRevision: access.member.authorizationRevision,
        episode,
      };
    });
  }

  function samePlayback(first, second) {
    return first.serverRevision === second.serverRevision &&
      first.channelRevision === second.channelRevision &&
      first.channelAclRevision === second.channelAclRevision &&
      first.membershipRevision === second.membershipRevision &&
      first.episode.revision === second.episode.revision &&
      first.episode.status === second.episode.status &&
      JSON.stringify(first.episode.media) === JSON.stringify(second.episode.media);
  }

  async function getServerPodcastEpisodeAccessV1(request) {
    const auth = requireActor(request, { verified: false });
    const input = playbackInput(request.data);
    const access = await authorizePlayback(auth, input, { consume: true });
    const media = canonicalMedia(access.episode.media, access.episode);
    const inspected = await episodeStorage.inspectAudio(media.storagePath);
    if (inspected.generation !== media.generation || inspected.size !== media.size ||
        inspected.contentType !== media.contentType) {
      fail("aborted", "The podcast episode audio changed. Try again.");
    }
    const expiresAtMillis = access.checkedAtMs + PODCAST_EPISODE_ACCESS_TTL_MS;
    const url = await episodeStorage.getSignedReadUrl(media.storagePath, {
      generation: media.generation,
      expiresAtMs: expiresAtMillis,
    });
    if (!safePlaybackUrl(url)) fail("failed-precondition", "Episode playback is unavailable.");
    const finalAccess = await authorizePlayback(auth, input);
    if (finalAccess.checkedAtMs >= expiresAtMillis || !samePlayback(access, finalAccess)) {
      fail("aborted", "Podcast episode authorization changed. Try again.");
    }
    return {
      schemaVersion: PODCAST_EPISODE_SCHEMA_VERSION,
      serverId: input.serverId,
      channelId: input.channelId,
      episodeId: input.episodeId,
      title: access.episode.title,
      expiresAtMillis,
      media: { url, ...media },
    };
  }

  async function reconcileServerPodcastEgressJobs({ limit = 20 } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 20 });
    const now = Timestamp.fromMillis(clock());
    const page = await db.collection("serverPodcastEgressJobs")
      .where("status", "==", "pending")
      .where("nextAttemptAt", "<=", now)
      .orderBy("nextAttemptAt")
      .limit(limit)
      .get();
    const processed = [];
    for (const document of page.docs) {
      canonicalJob(document);
      try {
        const result = await processPodcastEgressJob(document.id);
        if (result.processed) processed.push(document.id);
      } catch (_) {
        // The lease was released with a bounded retry time. One provider outage
        // must not prevent later jobs in this scheduled page from progressing.
      }
    }
    return { processed, scanned: page.size, hasMore: page.size === limit };
  }

  return Object.freeze({
    finalizeServerPodcastEpisodeV1,
    getServerPodcastEpisodeAccessV1,
    processPodcastEgressJob,
    publishServerPodcastEpisodeV1,
    reconcileServerPodcastEgressJobs,
    retryServerPodcastRecordingV1,
    startServerPodcastRecordingV1,
    stopServerPodcastRecordingV1,
  });
}

module.exports = {
  EPISODE_STATUSES,
  MAX_PODCAST_EPISODE_BYTES,
  MAX_PODCAST_EPISODE_DURATION_MS,
  MAX_PODCAST_EPISODE_TITLE_LENGTH,
  PODCAST_AUDIO_CONTENT_TYPE,
  PODCAST_EGRESS_LEASE_MS,
  PODCAST_EGRESS_POLL_MS,
  PODCAST_EPISODE_ACCESS_TTL_MS,
  PODCAST_EPISODE_SCHEMA_VERSION,
  PROVIDER_STATUSES,
  canonicalEpisode,
  canonicalJob,
  canonicalPodcastEpisodeId,
  canonicalRecordingState,
  createLiveKitPodcastEgressAdapter,
  createPodcastEpisodeStorageAdapter,
  createServerPodcastEpisodeService,
  podcastEpisodeStoragePath,
  safeProviderInfo,
};
