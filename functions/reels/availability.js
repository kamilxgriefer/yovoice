const {
  fail,
  isValidOpaqueUid,
  requireSafeInteger,
  timestampMillis,
} = require("../integrity/guards");
const { exactStoredObject } = require("./contract");

const REEL_AVAILABILITY_SCHEMA_VERSION = 2;
const HOUR_MS = 60 * 60 * 1000;
const MIN_REEL_AVAILABILITY_HOURS = 24;
const MAX_REEL_AVAILABILITY_HOURS = 720;
const DEFAULT_REEL_AVAILABILITY_HOURS = MIN_REEL_AVAILABILITY_HOURS;
const PERMANENT_AVAILABILITY = "permanent";

function validateAvailabilityHours(value) {
  if (value === PERMANENT_AVAILABILITY) return PERMANENT_AVAILABILITY;
  return requireSafeInteger(value, "availabilityHours", {
    min: MIN_REEL_AVAILABILITY_HOURS,
    max: MAX_REEL_AVAILABILITY_HOURS,
  });
}

function deadlineMillis(createdAtMs, availabilityHours) {
  if (availabilityHours === PERMANENT_AVAILABILITY) return null;
  const deadline = createdAtMs + availabilityHours * HOUR_MS;
  if (!Number.isSafeInteger(deadline)) {
    fail("data-loss", "The Reel availability deadline is malformed.");
  }
  return deadline;
}

function validateAvailabilitySnapshot(snapshot, expected = {}) {
  if (!snapshot?.exists) {
    if (expected.required === true) {
      fail("failed-precondition", "The Reel availability contract is unavailable.");
    }
    return null;
  }
  const raw = snapshot.data() ?? {};
  const availabilityHours = validateStoredAvailabilityHours(
    raw.availabilityHours,
  );
  const baseKeys = [
    "schemaVersion",
    "status",
    "ownerId",
    "reelId",
    "availabilityHours",
    "createdAt",
    "updatedAt",
  ];
  let expectedKeys;
  if (raw.status === "reserved") {
    expectedKeys = baseKeys;
  } else if (raw.status === "published") {
    expectedKeys = [
      ...baseKeys,
      "publishedAt",
      ...(availabilityHours === PERMANENT_AVAILABILITY ? [] : ["expiresAt"]),
    ];
  } else if (raw.status === "expired") {
    expectedKeys = [...baseKeys, "publishedAt", "expiredAt"];
  } else {
    fail("data-loss", "The Reel availability contract is malformed.");
  }
  const value = exactStoredObject(raw, expectedKeys, "Reel availability");
  const createdAtMs = timestampMillis(value.createdAt);
  const updatedAtMs = timestampMillis(value.updatedAt);
  const publishedAtMs = value.status === "reserved"
    ? null
    : timestampMillis(value.publishedAt);
  const expiredAtMs = value.status === "expired"
    ? timestampMillis(value.expiredAt)
    : null;
  const expectedDeadlineMs = createdAtMs === null
    ? null
    : deadlineMillis(createdAtMs, availabilityHours);
  const expiresAtMs = value.status === "published" &&
      availabilityHours !== PERMANENT_AVAILABILITY
    ? timestampMillis(value.expiresAt)
    : null;
  if (
    value.schemaVersion !== REEL_AVAILABILITY_SCHEMA_VERSION ||
    !isValidOpaqueUid(value.ownerId) ||
    typeof value.reelId !== "string" ||
    !/^[A-Za-z0-9_-]{1,128}$/u.test(value.reelId) ||
    value.reelId !== snapshot.id ||
    createdAtMs === null ||
    updatedAtMs === null ||
    updatedAtMs < createdAtMs ||
    (expected.ownerId !== undefined && value.ownerId !== expected.ownerId) ||
    (expected.reelId !== undefined && value.reelId !== expected.reelId) ||
    (publishedAtMs !== null && publishedAtMs < createdAtMs) ||
    (publishedAtMs !== null && updatedAtMs < publishedAtMs) ||
    (value.status === "published" &&
      availabilityHours !== PERMANENT_AVAILABILITY &&
      expiresAtMs !== expectedDeadlineMs) ||
    (value.status === "expired" &&
      (availabilityHours === PERMANENT_AVAILABILITY ||
        expiredAtMs === null ||
        expiredAtMs < expectedDeadlineMs ||
        updatedAtMs < expiredAtMs))
  ) {
    fail("data-loss", "The Reel availability contract is malformed.");
  }
  return {
    ...value,
    availabilityHours,
    createdAtMs,
    updatedAtMs,
    publishedAtMs,
    expiredAtMs,
    expiresAtMs,
  };
}

function validateStoredAvailabilityHours(value) {
  try {
    return validateAvailabilityHours(value);
  } catch (_) {
    fail("data-loss", "The Reel availability contract is malformed.");
  }
}

function sameAvailability(first, second) {
  if (first === null || second === null) return first === second;
  return [
    "schemaVersion",
    "status",
    "ownerId",
    "reelId",
    "availabilityHours",
    "createdAtMs",
    "updatedAtMs",
    "publishedAtMs",
    "expiredAtMs",
    "expiresAtMs",
  ].every((field) => first[field] === second[field]);
}

function publishedAvailability(
  snapshot,
  reel,
  nowMs,
  { allowExpired = false, required = false } = {},
) {
  const availability = validateAvailabilitySnapshot(snapshot, {
    ownerId: reel.authorId,
    reelId: reel.id,
    required,
  });
  if (availability === null) {
    return {
      schemaVersion: 1,
      status: "legacy",
      availabilityHours: PERMANENT_AVAILABILITY,
      expiresAtMs: null,
    };
  }
  const reelPublishedAtMs = timestampMillis(reel.publishedAt);
  if (
    availability.status === "reserved" ||
    availability.publishedAtMs !== reelPublishedAtMs
  ) {
    fail("data-loss", "The Reel availability contract is malformed.");
  }
  const isExpired = availability.status === "expired" ||
    (availability.expiresAtMs !== null && availability.expiresAtMs <= nowMs);
  if (isExpired && !allowExpired) {
    fail("failed-precondition", "The Reel has expired.");
  }
  return {
    ...availability,
    isExpired,
  };
}

module.exports = {
  DEFAULT_REEL_AVAILABILITY_HOURS,
  HOUR_MS,
  MAX_REEL_AVAILABILITY_HOURS,
  MIN_REEL_AVAILABILITY_HOURS,
  PERMANENT_AVAILABILITY,
  REEL_AVAILABILITY_SCHEMA_VERSION,
  deadlineMillis,
  publishedAvailability,
  sameAvailability,
  validateAvailabilityHours,
  validateAvailabilitySnapshot,
};
