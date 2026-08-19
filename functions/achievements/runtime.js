const {
  AchievementEngine,
  AchievementEventIntegrityError,
  eventFingerprint,
  eventIdFor,
  normalizeAchievementEvent,
} = require("./engine");
const { FirestoreAchievementRepository } = require("./firestore_repository");
const { eventsWithActorActiveDay } = require("./sources");

const ACHIEVEMENT_OUTBOX_SCHEMA_VERSION = 1;
const OUTBOX_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

class AchievementOutboxValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = "AchievementOutboxValidationError";
  }
}

function validDate(value, label) {
  const date = value instanceof Date
    ? value
    : typeof value?.toDate === "function"
      ? value.toDate()
      : null;
  if (!(date instanceof Date) || !Number.isFinite(date.getTime())) {
    throw new AchievementOutboxValidationError(`${label} is invalid.`);
  }
  return new Date(date.getTime());
}

function buildAchievementOutboxRecord(eventInput, createdAtInput) {
  const event = normalizeAchievementEvent(eventInput);
  const createdAt = validDate(createdAtInput, "createdAt");
  const expiresAtMs = createdAt.getTime() + OUTBOX_RETENTION_MS;
  if (!Number.isSafeInteger(expiresAtMs)) {
    throw new AchievementOutboxValidationError("Outbox retention overflows.");
  }
  return Object.freeze({
    schemaVersion: ACHIEVEMENT_OUTBOX_SCHEMA_VERSION,
    kind: "achievementEvent",
    status: "pending",
    eventId: eventIdFor(event),
    eventFingerprint: eventFingerprint(event),
    event: Object.freeze({ ...event }),
    createdAt,
    expiresAt: new Date(expiresAtMs),
  });
}

function normalizeAchievementOutboxRecord(raw, expectedId = null) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw) ||
      raw.schemaVersion !== ACHIEVEMENT_OUTBOX_SCHEMA_VERSION ||
      raw.kind !== "achievementEvent" || raw.status !== "pending") {
    throw new AchievementOutboxValidationError(
      "The achievement outbox record is not pending canonical data.",
    );
  }
  const event = normalizeAchievementEvent(raw.event);
  const eventId = eventIdFor(event);
  const fingerprint = eventFingerprint(event);
  if (raw.eventId !== eventId || raw.eventFingerprint !== fingerprint ||
      (expectedId !== null && expectedId !== eventId)) {
    throw new AchievementOutboxValidationError(
      "The achievement outbox identity does not match its event.",
    );
  }
  const createdAt = validDate(raw.createdAt, "createdAt");
  const expiresAt = validDate(raw.expiresAt, "expiresAt");
  if (expiresAt.getTime() !== createdAt.getTime() + OUTBOX_RETENTION_MS) {
    throw new AchievementOutboxValidationError(
      "The achievement outbox retention window is malformed.",
    );
  }
  return Object.freeze({ event, eventId, fingerprint, createdAt, expiresAt });
}

function createAchievementRuntime({
  repository,
  clock = () => new Date(),
  logger,
} = {}) {
  const resolvedRepository = repository ?? new FirestoreAchievementRepository();
  const engine = new AchievementEngine({ repository: resolvedRepository, clock, logger });

  async function processEvents(events) {
    if (!Array.isArray(events)) throw new TypeError("events must be an array.");
    const results = [];
    for (const event of events) results.push(await engine.process(event));
    return results;
  }

  async function processSourceEvent(event, { includeActiveDay = true } = {}) {
    if (!event) return { outcome: "skipped:invalid-source", results: [] };
    const normalized = normalizeAchievementEvent(event);
    const events = includeActiveDay
      ? eventsWithActorActiveDay(normalized, normalized.occurredAt)
      : [normalized];
    const results = await processEvents(events);
    return { outcome: "processed", results };
  }

  async function processOutboxRecord(raw, expectedId = null) {
    const record = normalizeAchievementOutboxRecord(raw, expectedId);
    const result = await engine.process(record.event);
    return { ...result, outboxId: record.eventId };
  }

  return Object.freeze({
    engine,
    processEvents,
    processOutboxRecord,
    processSourceEvent,
    repository: resolvedRepository,
  });
}

let defaultRuntime = null;

function getDefaultAchievementRuntime() {
  if (!defaultRuntime) defaultRuntime = createAchievementRuntime();
  return defaultRuntime;
}

module.exports = {
  ACHIEVEMENT_OUTBOX_SCHEMA_VERSION,
  AchievementEventIntegrityError,
  AchievementOutboxValidationError,
  OUTBOX_RETENTION_MS,
  buildAchievementOutboxRecord,
  createAchievementRuntime,
  getDefaultAchievementRuntime,
  normalizeAchievementOutboxRecord,
};
