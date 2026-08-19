const { createHash } = require("node:crypto");

const { achievementById, catalog } = require("./catalog");
const { isValidOpaqueUid } = require("./identity");
const {
  ALL_COUNTER_METRICS,
  applyAchievementEffect,
  buildUserAchievementProjection,
  isTimestampLike,
  normalizeProgress,
} = require("./model");

const COUNTER_METRIC_SET = new Set(ALL_COUNTER_METRICS);
const SOURCE_TYPE_PATTERN = /^[a-z][A-Za-z0-9._-]{1,63}$/u;

class AchievementEventValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = "AchievementEventValidationError";
  }
}

class AchievementEventIntegrityError extends Error {
  constructor(message) {
    super(message);
    this.name = "AchievementEventIntegrityError";
  }
}

function sha256(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function normalizeUid(value, label) {
  if (!isValidOpaqueUid(value)) {
    throw new AchievementEventValidationError(`${label} is not a safe id.`);
  }
  return value;
}

function normalizeOccurredAt(value) {
  if (value === null || value === undefined) return null;
  const date = value instanceof Date
    ? value
    : typeof value?.toDate === "function"
      ? value.toDate()
      : null;
  if (!(date instanceof Date) || !Number.isFinite(date.getTime())) {
    throw new AchievementEventValidationError(
      "occurredAt must be a valid server timestamp.",
    );
  }
  return new Date(date.getTime());
}

function normalizeAchievementEvent(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new AchievementEventValidationError("An achievement event is required.");
  }
  const sourceType = typeof input.sourceType === "string"
    ? input.sourceType.trim()
    : "";
  if (!SOURCE_TYPE_PATTERN.test(sourceType)) {
    throw new AchievementEventValidationError("sourceType is invalid.");
  }
  const sourceKey = typeof input.sourceKey === "string"
    ? input.sourceKey.trim()
    : "";
  if (!sourceKey || sourceKey.length > 1024) {
    throw new AchievementEventValidationError("sourceKey is invalid.");
  }
  const beneficiaryId = normalizeUid(input.beneficiaryId, "beneficiaryId");
  const actorId = input.actorId === null || input.actorId === undefined
    ? null
    : normalizeUid(input.actorId, "actorId");
  const metric = typeof input.metric === "string" ? input.metric.trim() : "";
  if (!COUNTER_METRIC_SET.has(metric)) {
    throw new AchievementEventValidationError(`Unknown metric: ${metric}.`);
  }
  const mode = input.mode ?? "increment";
  if (mode !== "increment" && mode !== "absolute") {
    throw new AchievementEventValidationError("mode must be increment or absolute.");
  }
  const normalized = {
    sourceType,
    sourceKey,
    beneficiaryId,
    actorId,
    metric,
    mode,
    occurredAt: normalizeOccurredAt(input.occurredAt),
  };
  if (mode === "increment") {
    if (!Number.isSafeInteger(input.delta) || input.delta <= 0) {
      throw new AchievementEventValidationError(
        "delta must be a positive safe integer.",
      );
    }
    normalized.delta = input.delta;
  } else {
    if (!Number.isSafeInteger(input.value) || input.value < 0) {
      throw new AchievementEventValidationError(
        "value must be a non-negative safe integer.",
      );
    }
    if (!Number.isSafeInteger(input.version) || input.version < 0) {
      throw new AchievementEventValidationError(
        "absolute events require a non-negative safe version.",
      );
    }
    normalized.value = input.value;
    normalized.version = input.version;
  }
  return Object.freeze(normalized);
}

function canonicalEventIdentity(event) {
  return `v1|${event.sourceType}|${event.sourceKey}|${event.metric}`;
}

function eventIdFor(eventInput) {
  const event = normalizeAchievementEvent(eventInput);
  return `v1_${sha256(canonicalEventIdentity(event))}`;
}

function eventFingerprint(event) {
  return sha256(JSON.stringify({
    sourceType: event.sourceType,
    sourceKey: event.sourceKey,
    beneficiaryId: event.beneficiaryId,
    actorId: event.actorId,
    metric: event.metric,
    mode: event.mode,
    delta: event.delta ?? null,
    value: event.value ?? null,
    version: event.version ?? null,
    occurredAt: event.occurredAt?.toISOString() ?? null,
  }));
}

function buildLedgerRecord(event, eventId, fingerprint, processedAt, outcome) {
  return {
    schemaVersion: 1,
    catalogVersion: catalog.catalogVersion,
    eventId,
    eventFingerprint: fingerprint,
    sourceType: event.sourceType,
    sourceKeyHash: sha256(event.sourceKey),
    beneficiaryId: event.beneficiaryId,
    actorId: event.actorId,
    metric: event.metric,
    mode: event.mode,
    ...(event.mode === "increment"
      ? { delta: event.delta }
      : { value: event.value, version: event.version }),
    sourceOccurredAt: event.occurredAt,
    processedAt,
    outcome,
  };
}

function notificationIdFor(achievementId) {
  if (!achievementById(achievementId)) {
    throw new AchievementEventValidationError("Unknown achievement id.");
  }
  return `achievementUnlocked_${achievementId}`;
}

function buildAchievementNotification(achievementId, processedAt) {
  const achievement = achievementById(achievementId);
  if (!achievement) {
    throw new AchievementEventValidationError("Unknown achievement id.");
  }
  const notificationId = notificationIdFor(achievementId);
  return {
    id: notificationId,
    data: {
      type: "achievementUnlocked",
      actorId: "yovoice-system",
      actorName: "YO Voice",
      actorPhotoUrl: null,
      targetId: achievement.id,
      targetLabel: achievement.title,
      isRead: false,
      createdAt: processedAt,
      dedupeKey: notificationId,
      bellSuppressed: false,
    },
  };
}

function assertRepository(repository) {
  if (!repository || typeof repository.runTransaction !== "function") {
    throw new TypeError("An achievement transaction repository is required.");
  }
}

class AchievementEngine {
  constructor({ repository, clock = () => new Date(), logger = console }) {
    assertRepository(repository);
    if (typeof clock !== "function") throw new TypeError("clock must be a function.");
    if (typeof logger?.error !== "function") {
      throw new TypeError("logger must expose error().");
    }
    this.repository = repository;
    this.clock = clock;
    this.logger = logger;
  }

  // True when the derived event, re-fingerprinted at the stored entry's own
  // observation time, matches the stored fingerprint exactly — i.e. the two
  // agree on every canonical field except occurredAt. Sharing an eventId
  // already pins sourceType, sourceKey and metric to the same values.
  isTimeOnlyVariant(event, existingEvent) {
    try {
      const storedTimeFingerprint = eventFingerprint({
        ...event,
        occurredAt: normalizeOccurredAt(existingEvent.sourceOccurredAt ?? null),
      });
      return storedTimeFingerprint === existingEvent.eventFingerprint;
    } catch (_) {
      // An unreadable stored observation time cannot prove the benign case;
      // report it as a real collision rather than crash into a retry loop.
      return false;
    }
  }

  async process(eventInput) {
    const event = normalizeAchievementEvent(eventInput);
    const eventId = eventIdFor(event);
    const fingerprint = eventFingerprint(event);
    const clockValue = this.clock();
    const processedAt = clockValue instanceof Date
      ? new Date(clockValue.getTime())
      : typeof clockValue?.toDate === "function"
        ? clockValue.toDate()
        : null;
    if (!isTimestampLike(processedAt)) {
      throw new TypeError("The achievement engine clock returned an invalid date.");
    }

    const result = await this.repository.runTransaction(async (transaction) => {
      const existingEvent = await transaction.getEvent(eventId);
      if (existingEvent) {
        if (existingEvent.eventFingerprint !== fingerprint) {
          // The canonical slot for this identity already holds different
          // content, and the difference is permanent: redelivery can only
          // ever derive the same fingerprint again, so throwing here turns
          // an at-least-once redelivery into an infinite retry loop
          // (2026-08-18 production incident). Both branches below are
          // therefore terminal and neither applies the event or touches the
          // stored entry — dedup always keeps the first write.
          //
          // Some identities deliberately collapse repeatable occurrences
          // (an active day, a community re-join, a reaction re-added): the
          // recurrence arrives with identical content except for its
          // observation time. That is a replay of the identity, not an
          // integrity violation, so it stays quiet. Anything else diverging
          // is a real collision and is reported loudly.
          if (this.isTimeOnlyVariant(event, existingEvent)) {
            return {
              outcome: "replayed",
              eventId,
              newVerifiedTitleIds: [],
              newDisplayTitleIds: [],
              notificationIds: [],
            };
          }
          return {
            outcome: "collision",
            eventId,
            newVerifiedTitleIds: [],
            newDisplayTitleIds: [],
            notificationIds: [],
            collision: {
              derivedFingerprint: fingerprint,
              storedFingerprint: existingEvent.eventFingerprint ?? null,
              storedSourceType: existingEvent.sourceType ?? null,
              storedOutcome: existingEvent.outcome ?? null,
              storedProcessedAt: existingEvent.processedAt ?? null,
            },
          };
        }
        return {
          outcome: "replayed",
          eventId,
          newVerifiedTitleIds: [],
          newDisplayTitleIds: [],
          notificationIds: [],
        };
      }

      const user = await transaction.getUser(event.beneficiaryId);
      if (!user) {
        return {
          outcome: "skipped:missing-user",
          eventId,
          newVerifiedTitleIds: [],
          newDisplayTitleIds: [],
          notificationIds: [],
        };
      }
      const storedProgress = await transaction.getProgress(event.beneficiaryId);
      const progress = normalizeProgress(storedProgress, { legacyUser: user });
      const effect = event.mode === "increment"
        ? { metric: event.metric, mode: event.mode, delta: event.delta }
        : {
            metric: event.metric,
            mode: event.mode,
            value: event.value,
            version: event.version,
          };
      const applied = applyAchievementEffect(progress, effect, processedAt);

      const notificationPlans = [];
      for (const achievementId of applied.newDisplayTitleIds) {
        const notification = buildAchievementNotification(
          achievementId,
          processedAt,
        );
        const existingNotification = await transaction.getNotification(
          event.beneficiaryId,
          notification.id,
        );
        if (!existingNotification) notificationPlans.push(notification);
      }

      const outcome = applied.stale ? "stale" : "applied";
      await transaction.createEvent(
        eventId,
        buildLedgerRecord(event, eventId, fingerprint, processedAt, outcome),
      );
      if (!applied.stale) {
        const stored = { ...applied.progress, updatedAt: processedAt };
        await transaction.setProgress(event.beneficiaryId, stored);
        await transaction.setUserProjection(
          event.beneficiaryId,
          buildUserAchievementProjection(stored, processedAt),
        );
        for (const notification of notificationPlans) {
          await transaction.createNotification(
            event.beneficiaryId,
            notification.id,
            notification.data,
          );
        }
      }

      return {
        outcome,
        eventId,
        newVerifiedTitleIds: applied.newVerifiedTitleIds,
        newDisplayTitleIds: applied.newDisplayTitleIds,
        notificationIds: notificationPlans.map((item) => item.id),
      };
    });

    if (result.outcome === "collision") {
      // Reported outside the transaction so an internal transaction retry
      // cannot emit the forensic record twice.
      this.logger.error(
        `Canonical source collision for ${result.eventId}: the stored ledger ` +
          "entry wins and the mismatched event is dropped without retry.",
        {
          eventId: result.eventId,
          sourceType: event.sourceType,
          metric: event.metric,
          beneficiaryId: event.beneficiaryId,
          ...result.collision,
        },
      );
    }
    return result;
  }
}

module.exports = {
  AchievementEngine,
  AchievementEventIntegrityError,
  AchievementEventValidationError,
  buildAchievementNotification,
  canonicalEventIdentity,
  eventFingerprint,
  eventIdFor,
  normalizeAchievementEvent,
  notificationIdFor,
};
