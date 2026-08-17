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
// A signed token with no `exp` verifies forever, and the receiver's
// `clockTolerance` is skew tolerance for `exp`/`nbf`, not a maximum age. This
// is therefore the only bound on how old a captured delivery may be. Replay is
// already a no-op against the interval-union ledger; what this buys is that
// replay is not FREE, so the state-machine paths behind it cannot be driven
// cheaply. Symmetric, so a future-dated event is refused too.
const MAX_WEBHOOK_EVENT_AGE_MS = 10 * 60 * 1000;

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
  now = () => Date.now(),
  maximumEventAgeMs = MAX_WEBHOOK_EVENT_AGE_MS,
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
  //
  // Two precise notes about what this verification does and does not do, so
  // the next reader does not credit it with more than it performs:
  //
  //  - The JWT SIGNATURE comparison is constant-time (jose's HS* path uses
  //    crypto.timingSafeEqual). The `sha256` body-digest claim is then checked
  //    with an ordinary `!==` string compare, NOT a timing-safe one. That is
  //    not exploitable — the claim is already authenticated by the signature,
  //    and an attacker who could forge it would not need the timing — but the
  //    two comparisons are not the same and should not be described as one.
  //  - The receiver does NOT pin `algorithms`, so HS384 and HS512 are accepted
  //    alongside HS256. Also not exploitable: every HS* variant requires this
  //    same secret, and an asymmetric `alg` cannot be substituted because jose
  //    rejects a non-HMAC algorithm for a symmetric key. If a verifier is ever
  //    constructed here directly rather than by the SDK, pin ['HS256'].
  const event = await verifier.receive(body, authorization, false, clockTolerance);
  const normalized = normalizeLiveKitWebhookEvent(event);
  // The receiver verifies the signature but NOT the age of what was signed:
  // an authentic token carrying no `exp` claim stays valid indefinitely, and
  // the `sha256` claim binds the body to the token, not the token to a moment.
  // The event's own `created_at` is inside the signed body, so it cannot be
  // moved without invalidating the signature — which makes it the one
  // trustworthy clock available here.
  if (normalized && Math.abs(now() - normalized.createdAtMs) > maximumEventAgeMs) {
    throw new VoiceWebhookValidationError(
      "The LiveKit webhook event is outside its freshness window.",
    );
  }
  return normalized;
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
    // SATURATION, NOT REFUSAL. This bound used to throw, which propagated out
    // as a permanent 400 and left the session document open forever — so past
    // 256 disjoint intervals in a UTC day, every further close was refused and
    // its credit lost. 256 reconnects in 24 hours is one every 5.6 minutes,
    // which an ordinary phone on a bad network reaches without trying, so the
    // bound was hurting exactly the users it was not aimed at. It also bounded
    // no abuse: a farmer stays connected rather than reconnecting.
    //
    // The ledger is what saturates; the state machine must not. The previous
    // union is returned unchanged so the day's stored intervals stay canonical
    // and bounded, zero seconds are credited, and the caller still closes the
    // session normally.
    return { intervals: previousUnion, addedSeconds: 0, saturated: true };
  }
  const previousSeconds = Math.floor(coveredMilliseconds(previousUnion) / 1000);
  const nextSeconds = Math.floor(coveredMilliseconds(nextUnion) / 1000);
  return {
    intervals: nextUnion,
    addedSeconds: Math.max(nextSeconds - previousSeconds, 0),
    saturated: false,
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
  let saturated = false;
  for (const part of parts) {
    const voice = mergeBillableInterval(nextVoiceDays[part.day], part);
    nextVoiceDays[part.day] = voice.intervals;
    voiceSecondsAdded += voice.addedSeconds;
    if (voice.saturated) saturated = true;
    if (session.isHost === true) {
      const host = mergeBillableInterval(nextHostDays[part.day], part);
      nextHostDays[part.day] = host.intervals;
      hostSecondsAdded += host.addedSeconds;
      if (host.saturated) saturated = true;
    }
  }
  return {
    interval,
    voiceIntervalsByDay: nextVoiceDays,
    hostIntervalsByDay: nextHostDays,
    voiceSecondsAdded,
    hostSecondsAdded,
    saturated,
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
  MAX_WEBHOOK_EVENT_AGE_MS,
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
