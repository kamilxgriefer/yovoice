const { WebhookReceiver } = require("livekit-server-sdk");
const { isValidOpaqueUid } = require("./identity");

const SUPPORTED_VOICE_EVENTS = new Set([
  "participant_joined",
  "participant_left",
  "participant_connection_aborted",
  "room_finished",
]);
const DEFAULT_MAX_SESSION_SECONDS = 24 * 60 * 60;
const MAX_VOICE_DAY_BUCKETS = 2;
const MAX_VOICE_INTERVALS_PER_DAY = 256;
const MILLISECONDS_PER_DAY = 24 * 60 * 60 * 1000;

class VoiceWebhookValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = "VoiceWebhookValidationError";
  }
}

function nonEmpty(value, maximum = 128) {
  return typeof value === "string" && value.trim() && value.trim().length <= maximum
    ? value.trim()
    : null;
}

function opaqueUid(value) {
  return isValidOpaqueUid(value) ? value : null;
}

function bigintMilliseconds(value, multiplier = 1) {
  try {
    const numeric = typeof value === "bigint" ? value : BigInt(value ?? 0);
    const scaled = numeric * BigInt(multiplier);
    return scaled > 0n && scaled <= BigInt(Number.MAX_SAFE_INTEGER)
      ? Number(scaled)
      : null;
  } catch (_) {
    return null;
  }
}

function normalizeLiveKitWebhookEvent(event) {
  const type = nonEmpty(event?.event, 80);
  if (!SUPPORTED_VOICE_EVENTS.has(type)) return null;
  const eventId = nonEmpty(event?.id, 128);
  const roomSid = nonEmpty(event?.room?.sid, 128);
  const roomName = nonEmpty(event?.room?.name, 128);
  const createdAtMs = bigintMilliseconds(event?.createdAt, 1000);
  if (!eventId || !roomSid || !roomName || !createdAtMs) {
    throw new VoiceWebhookValidationError("LiveKit webhook identity is incomplete.");
  }
  if (type === "room_finished") {
    return Object.freeze({ type, eventId, roomSid, roomName, createdAtMs });
  }
  const participantSid = nonEmpty(event?.participant?.sid, 128);
  const participantIdentity = opaqueUid(event?.participant?.identity);
  const joinedAtMs = bigintMilliseconds(event?.participant?.joinedAtMs) ??
    bigintMilliseconds(event?.participant?.joinedAt, 1000);
  if (!participantSid || !participantIdentity) {
    throw new VoiceWebhookValidationError(
      "LiveKit participant webhook identity is incomplete.",
    );
  }
  if (type === "participant_joined" && !joinedAtMs) {
    throw new VoiceWebhookValidationError("LiveKit join time is missing.");
  }
  return Object.freeze({
    type,
    eventId,
    roomSid,
    roomName,
    createdAtMs,
    participantSid,
    participantIdentity,
    joinedAtMs,
  });
}

async function receiveSignedLiveKitWebhook({
  apiKey,
  apiSecret,
  rawBody,
  authorization,
  clockTolerance = "30s",
  receiver = null,
}) {
  if (!nonEmpty(apiKey, 500) || !nonEmpty(apiSecret, 1000)) {
    throw new VoiceWebhookValidationError("LiveKit webhook secrets are required.");
  }
  if (!(typeof rawBody === "string" || Buffer.isBuffer(rawBody))) {
    throw new VoiceWebhookValidationError(
      "The exact raw webhook body is required for signature verification.",
    );
  }
  if (!nonEmpty(authorization, 4096)) {
    throw new VoiceWebhookValidationError("LiveKit authorization is required.");
  }
  const body = Buffer.isBuffer(rawBody) ? rawBody.toString("utf8") : rawBody;
  const verifier = receiver ?? new WebhookReceiver(apiKey, apiSecret);
  // skipAuth is deliberately false. Token issuance, client telemetry and parsed
  // JSON objects are never accepted as evidence of connected voice time.
  const event = await verifier.receive(body, authorization, false, clockTolerance);
  return normalizeLiveKitWebhookEvent(event);
}

function voiceSessionFromJoin(webhook, canonicalRoom) {
  if (webhook?.type !== "participant_joined") {
    throw new VoiceWebhookValidationError("A signed participant join is required.");
  }
  const roomId = nonEmpty(canonicalRoom?.id, 128);
  const hostId = opaqueUid(canonicalRoom?.hostId);
  if (!roomId || roomId !== webhook.roomName || !hostId) {
    throw new VoiceWebhookValidationError(
      "The LiveKit room is not bound to a canonical YO Voice room.",
    );
  }
  return Object.freeze({
    roomId,
    roomSid: webhook.roomSid,
    participantSid: webhook.participantSid,
    userId: webhook.participantIdentity,
    joinedAtMs: webhook.joinedAtMs,
    isHost: hostId === webhook.participantIdentity,
    joinEventId: webhook.eventId,
  });
}

function closeVoiceSession(
  session,
  webhook,
  { maximumSessionSeconds = DEFAULT_MAX_SESSION_SECONDS } = {},
) {
  if (!Number.isSafeInteger(maximumSessionSeconds) || maximumSessionSeconds <= 0) {
    throw new VoiceWebhookValidationError("A safe maximum session length is required.");
  }
  if (maximumSessionSeconds > Math.floor(Number.MAX_SAFE_INTEGER / 1000)) {
    throw new VoiceWebhookValidationError("The maximum session length is too large.");
  }
  if (!session || !opaqueUid(session.userId) || !nonEmpty(session.roomSid) ||
      !nonEmpty(session.participantSid) ||
      !Number.isSafeInteger(session.joinedAtMs) || session.joinedAtMs <= 0) {
    throw new VoiceWebhookValidationError("The canonical voice session is invalid.");
  }
  if (!webhook || ![
    "participant_left",
    "participant_connection_aborted",
    "room_finished",
  ].includes(webhook.type) || webhook.roomSid !== session.roomSid) {
    return null;
  }
  if (webhook.type !== "room_finished" &&
      (webhook.participantSid !== session.participantSid ||
       webhook.participantIdentity !== session.userId)) {
    return null;
  }
  const rawMilliseconds = webhook.createdAtMs - session.joinedAtMs;
  if (!Number.isSafeInteger(rawMilliseconds) || rawMilliseconds <= 0) return null;
  const maximumMilliseconds = maximumSessionSeconds * 1000;
  const endedAtMs = session.joinedAtMs + Math.min(
    rawMilliseconds,
    maximumMilliseconds,
  );
  return Object.freeze({
    startMs: session.joinedAtMs,
    endMs: endedAtMs,
    capped: rawMilliseconds > maximumMilliseconds,
    closeEventId: webhook.eventId,
  });
}

function coveredMilliseconds(intervals) {
  return intervals.reduce((total, item) => total + item.endMs - item.startMs, 0);
}

function validateDailyInterval(item, message) {
  if (!Number.isSafeInteger(item?.startMs) ||
      !Number.isSafeInteger(item?.endMs) || item.startMs < 0 ||
      item.endMs <= item.startMs) {
    throw new VoiceWebhookValidationError(message);
  }
  const start = new Date(item.startMs);
  const nextDayMs = Date.UTC(
    start.getUTCFullYear(),
    start.getUTCMonth(),
    start.getUTCDate() + 1,
  );
  if (!Number.isSafeInteger(nextDayMs) || item.endMs > nextDayMs ||
      item.endMs - item.startMs > MILLISECONDS_PER_DAY) {
    throw new VoiceWebhookValidationError(message);
  }
  return {
    day: start.toISOString().slice(0, 10),
    startMs: item.startMs,
    endMs: item.endMs,
  };
}

function mergeBillableInterval(existingIntervals, addedInterval) {
  const rawExisting = Array.isArray(existingIntervals) ? existingIntervals : [];
  if (rawExisting.length > MAX_VOICE_INTERVALS_PER_DAY) {
    throw new VoiceWebhookValidationError(
      "The daily voice interval ledger exceeds its safe bound.",
    );
  }
  const existing = rawExisting
    .map((item) => {
      return validateDailyInterval(
        item,
        "Stored billable voice intervals are malformed.",
      );
    })
    .sort((left, right) => left.startMs - right.startMs || left.endMs - right.endMs);
  const added = validateDailyInterval(
    addedInterval,
    "A valid billable interval is required.",
  );
  if (existing.some((interval) => interval.day !== added.day)) {
    throw new VoiceWebhookValidationError(
      "Stored billable voice intervals cross UTC day buckets.",
    );
  }
  // Compute the previous union independently; existing storage is allowed to
  // contain adjacent fragments and is canonicalised by every update.
  const canonicalise = (items) => {
    const merged = [];
    for (const interval of items) {
      const previous = merged[merged.length - 1];
      if (!previous || interval.startMs > previous.endMs) {
        merged.push({ startMs: interval.startMs, endMs: interval.endMs });
      } else {
        previous.endMs = Math.max(previous.endMs, interval.endMs);
      }
    }
    return merged;
  };
  const previousUnion = canonicalise(existing);
  const nextUnion = canonicalise([...existing, added].sort(
    (left, right) => left.startMs - right.startMs || left.endMs - right.endMs,
  ));
  if (nextUnion.length > MAX_VOICE_INTERVALS_PER_DAY) {
    throw new VoiceWebhookValidationError(
      "The daily voice interval ledger exceeds its safe bound.",
    );
  }
  const previousSeconds = Math.floor(coveredMilliseconds(previousUnion) / 1000);
  const nextSeconds = Math.floor(coveredMilliseconds(nextUnion) / 1000);
  return {
    intervals: nextUnion,
    addedSeconds: Math.max(nextSeconds - previousSeconds, 0),
  };
}

function validateVoiceDayBuckets(value, allowedDays, label) {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      Object.getPrototypeOf(value) !== Object.prototype) {
    throw new VoiceWebhookValidationError(`${label} must be a plain object.`);
  }
  const entries = Object.entries(value);
  if (entries.length > MAX_VOICE_DAY_BUCKETS) {
    throw new VoiceWebhookValidationError(`${label} exceeds its safe day bound.`);
  }
  for (const [day, intervals] of entries) {
    if (!allowedDays.has(day) || !Array.isArray(intervals)) {
      throw new VoiceWebhookValidationError(`${label} contains an invalid day.`);
    }
    if (intervals.length > MAX_VOICE_INTERVALS_PER_DAY) {
      throw new VoiceWebhookValidationError(
        `${label} exceeds its safe interval bound.`,
      );
    }
  }
}

function splitIntervalByUtcDay(interval) {
  if (!Number.isSafeInteger(interval?.startMs) ||
      !Number.isSafeInteger(interval?.endMs) || interval.startMs < 0 ||
      interval.endMs <= interval.startMs) {
    throw new VoiceWebhookValidationError("A valid UTC voice interval is required.");
  }
  const parts = [];
  let cursor = interval.startMs;
  while (cursor < interval.endMs) {
    const date = new Date(cursor);
    const nextDay = Date.UTC(
      date.getUTCFullYear(),
      date.getUTCMonth(),
      date.getUTCDate() + 1,
    );
    const endMs = Math.min(interval.endMs, nextDay);
    parts.push({
      day: date.toISOString().slice(0, 10),
      startMs: cursor,
      endMs,
    });
    cursor = endMs;
  }
  return parts;
}

function planVoiceSessionCredit({
  session,
  closeWebhook,
  voiceIntervalsByDay = {},
  hostIntervalsByDay = {},
  maximumSessionSeconds = DEFAULT_MAX_SESSION_SECONDS,
}) {
  const interval = closeVoiceSession(session, closeWebhook, {
    maximumSessionSeconds,
  });
  if (!interval) return null;
  const parts = splitIntervalByUtcDay(interval);
  const allowedDays = new Set(parts.map((part) => part.day));
  validateVoiceDayBuckets(
    voiceIntervalsByDay,
    allowedDays,
    "voiceIntervalsByDay",
  );
  validateVoiceDayBuckets(
    hostIntervalsByDay,
    allowedDays,
    "hostIntervalsByDay",
  );
  const nextVoiceDays = { ...voiceIntervalsByDay };
  const nextHostDays = { ...hostIntervalsByDay };
  let voiceSecondsAdded = 0;
  let hostSecondsAdded = 0;
  for (const part of parts) {
    const voice = mergeBillableInterval(nextVoiceDays[part.day], part);
    nextVoiceDays[part.day] = voice.intervals;
    voiceSecondsAdded += voice.addedSeconds;
    if (session.isHost === true) {
      const host = mergeBillableInterval(nextHostDays[part.day], part);
      nextHostDays[part.day] = host.intervals;
      hostSecondsAdded += host.addedSeconds;
    }
  }
  return {
    interval,
    voiceIntervalsByDay: nextVoiceDays,
    hostIntervalsByDay: nextHostDays,
    voiceSecondsAdded,
    hostSecondsAdded,
  };
}

function voiceAchievementEvents(session, plan) {
  if (!session || !plan) return [];
  const sourceKey = `livekit/${session.roomSid}/participants/${session.participantSid}`;
  const common = {
    sourceKey,
    beneficiaryId: session.userId,
    actorId: session.userId,
    mode: "increment",
    occurredAt: new Date(plan.interval.endMs),
  };
  const events = [];
  if (plan.voiceSecondsAdded > 0) {
    events.push({
      ...common,
      sourceType: "liveKitVoiceSession",
      metric: "voiceSeconds",
      delta: plan.voiceSecondsAdded,
    });
  }
  if (session.isHost === true && plan.hostSecondsAdded > 0) {
    events.push({
      ...common,
      sourceType: "liveKitHostSession",
      metric: "hostSeconds",
      delta: plan.hostSecondsAdded,
    });
  }
  return events;
}

module.exports = {
  DEFAULT_MAX_SESSION_SECONDS,
  MAX_VOICE_DAY_BUCKETS,
  MAX_VOICE_INTERVALS_PER_DAY,
  SUPPORTED_VOICE_EVENTS,
  VoiceWebhookValidationError,
  closeVoiceSession,
  mergeBillableInterval,
  normalizeLiveKitWebhookEvent,
  planVoiceSessionCredit,
  receiveSignedLiveKitWebhook,
  splitIntervalByUtcDay,
  voiceAchievementEvents,
  voiceSessionFromJoin,
};
