const { achievementById, catalog } = require("./catalog");

const ACHIEVEMENT_SCHEMA_VERSION = 1;
const INTERNAL_METRICS = Object.freeze(["voiceSeconds", "hostSeconds"]);
const ALL_COUNTER_METRICS = Object.freeze([
  ...catalog.metrics,
  ...INTERNAL_METRICS,
]);
const ALL_COUNTER_METRIC_SET = new Set(ALL_COUNTER_METRICS);

// friendCount and followerCount remain projections of the authoritative social
// graph. Achievement processing must never overwrite them after an unrelated
// event with a stale snapshot.
const METRIC_TO_USER_FIELD = Object.freeze({
  messages: "messageCount",
  voiceMinutes: "voiceMinutes",
  rooms: "roomCount",
  communities: "communityCount",
  reactions: "reactionCount",
  hostMinutes: "hostMinutes",
  activeDays: "activeDays",
  moments: "momentCount",
});

function safeNonNegativeInteger(value, fallback = 0) {
  return Number.isSafeInteger(value) && value >= 0 ? value : fallback;
}

function addWithoutOverflow(left, right) {
  const value = left + right;
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError("Achievement counter exceeds the safe integer range.");
  }
  return value;
}

function emptyCounterMap(metrics = ALL_COUNTER_METRICS) {
  return Object.fromEntries(metrics.map((metric) => [metric, 0]));
}

function normalizeCounterMap(raw, metrics = ALL_COUNTER_METRICS) {
  const input = raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw
    : {};
  return Object.fromEntries(
    metrics.map((metric) => [
      metric,
      safeNonNegativeInteger(input[metric]),
    ]),
  );
}

function isTimestampLike(value) {
  if (value instanceof Date) return Number.isFinite(value.getTime());
  if (!value || typeof value.toDate !== "function") return false;
  try {
    const date = value.toDate();
    return date instanceof Date && Number.isFinite(date.getTime());
  } catch (_) {
    return false;
  }
}

function normalizeTitleIds(raw) {
  const values = Array.isArray(raw) ? raw : [];
  const known = new Set(
    values.filter((value) => typeof value === "string" && achievementById(value)),
  );
  return catalog.definitions
    .map((definition) => definition.id)
    .filter((id) => known.has(id));
}

function normalizeTimestampMap(raw, allowedIds) {
  const input = raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw
    : {};
  const allowed = new Set(allowedIds);
  const output = {};
  for (const definition of catalog.definitions) {
    const value = input[definition.id];
    if (allowed.has(definition.id) && isTimestampLike(value)) {
      output[definition.id] = value;
    }
  }
  return output;
}

function availableTitleIds(progress) {
  // Legacy title fields were historically writable by clients. They remain in
  // the private progress document for bounded reconciliation/audit only and
  // can never confer XP, selection rights or a public badge.
  const available = new Set(progress.verifiedUnlockedTitleIds);
  return catalog.definitions
    .map((definition) => definition.id)
    .filter((id) => available.has(id));
}

function displayUnlockTimestamps(progress) {
  const output = {};
  for (const id of availableTitleIds(progress)) {
    const timestamp = progress.verifiedUnlockedTitleTimestamps[id];
    if (timestamp !== undefined) output[id] = timestamp;
  }
  return output;
}

function legacyProgressFromUser(user) {
  const data = user && typeof user === "object" ? user : {};
  const legacyMetricFloors = emptyCounterMap(catalog.metrics);
  for (const metric of catalog.metrics) {
    const field = metric === "friends"
      ? "friendCount"
      : metric === "followers"
        ? "followerCount"
        : METRIC_TO_USER_FIELD[metric];
    legacyMetricFloors[metric] = safeNonNegativeInteger(data[field]);
  }
  return {
    schemaVersion: ACHIEVEMENT_SCHEMA_VERSION,
    catalogVersion: catalog.catalogVersion,
    verifiedMetrics: emptyCounterMap(),
    legacyMetricFloors,
    peakMetrics: emptyCounterMap(catalog.metrics),
    metricVersions: {},
    verifiedUnlockedTitleIds: [],
    verifiedUnlockedTitleTimestamps: {},
    legacyUnlockedTitleIds: normalizeTitleIds(data.unlockedTitleIds),
    // This raw shape is written verbatim to achievementProgress during the
    // migration bootstrap, and Firestore rejects undefined values. A legacy
    // skeleton profile without these fields must map to null, not undefined.
    legacyUnlockedTitleTimestamps: data.unlockedTitleTimestamps ?? null,
    selectedTitleId: data.selectedTitleId ?? null,
  };
}

function normalizeProgress(raw, { legacyUser = null } = {}) {
  const source = raw && typeof raw === "object"
    ? raw
    : legacyProgressFromUser(legacyUser);
  const verifiedMetrics = normalizeCounterMap(source.verifiedMetrics);

  // A migrated deployment may initially know verified whole minutes but not
  // seconds. Convert once so later signed voice-session deltas keep progressing.
  if (verifiedMetrics.voiceSeconds === 0 && verifiedMetrics.voiceMinutes > 0) {
    verifiedMetrics.voiceSeconds = verifiedMetrics.voiceMinutes <=
        Math.floor(Number.MAX_SAFE_INTEGER / 60)
      ? verifiedMetrics.voiceMinutes * 60
      : Number.MAX_SAFE_INTEGER;
  }
  if (verifiedMetrics.hostSeconds === 0 && verifiedMetrics.hostMinutes > 0) {
    verifiedMetrics.hostSeconds = verifiedMetrics.hostMinutes <=
        Math.floor(Number.MAX_SAFE_INTEGER / 60)
      ? verifiedMetrics.hostMinutes * 60
      : Number.MAX_SAFE_INTEGER;
  }
  verifiedMetrics.voiceMinutes = Math.max(
    verifiedMetrics.voiceMinutes,
    Math.floor(verifiedMetrics.voiceSeconds / 60),
  );
  verifiedMetrics.hostMinutes = Math.max(
    verifiedMetrics.hostMinutes,
    Math.floor(verifiedMetrics.hostSeconds / 60),
  );

  const legacyMetricFloors = normalizeCounterMap(
    source.legacyMetricFloors,
    catalog.metrics,
  );
  const normalizedPeaks = normalizeCounterMap(
    source.peakMetrics,
    catalog.metrics,
  );
  const peakMetrics = Object.fromEntries(
    catalog.metrics.map((metric) => [
      metric,
      Math.max(normalizedPeaks[metric], verifiedMetrics[metric]),
    ]),
  );
  const metricVersionsInput = source.metricVersions &&
      typeof source.metricVersions === "object" &&
      !Array.isArray(source.metricVersions)
    ? source.metricVersions
    : {};
  const metricVersions = {};
  for (const metric of ALL_COUNTER_METRICS) {
    const version = metricVersionsInput[metric];
    if (Number.isSafeInteger(version) && version >= 0) {
      metricVersions[metric] = version;
    }
  }

  const verifiedUnlockedTitleIds = normalizeTitleIds(
    source.verifiedUnlockedTitleIds,
  );
  const legacyUnlockedTitleIds = normalizeTitleIds(
    source.legacyUnlockedTitleIds,
  );
  const progress = {
    schemaVersion: ACHIEVEMENT_SCHEMA_VERSION,
    catalogVersion: catalog.catalogVersion,
    verifiedMetrics,
    legacyMetricFloors,
    peakMetrics,
    metricVersions,
    verifiedUnlockedTitleIds,
    verifiedUnlockedTitleTimestamps: normalizeTimestampMap(
      source.verifiedUnlockedTitleTimestamps,
      verifiedUnlockedTitleIds,
    ),
    legacyUnlockedTitleIds,
    legacyUnlockedTitleTimestamps: normalizeTimestampMap(
      source.legacyUnlockedTitleTimestamps,
      legacyUnlockedTitleIds,
    ),
    selectedTitleId: typeof source.selectedTitleId === "string"
      ? source.selectedTitleId
      : null,
  };
  if (!availableTitleIds(progress).includes(progress.selectedTitleId)) {
    progress.selectedTitleId = null;
  }
  return progress;
}

function applyAchievementEffect(rawProgress, effect, processedAt) {
  if (!effect || !ALL_COUNTER_METRIC_SET.has(effect.metric)) {
    throw new TypeError("A known achievement metric is required.");
  }
  if (!isTimestampLike(processedAt)) {
    throw new TypeError("A server processing timestamp is required.");
  }
  const progress = normalizeProgress(rawProgress);
  const beforeDisplay = new Set(availableTitleIds(progress));
  const verifiedMetrics = { ...progress.verifiedMetrics };
  const peakMetrics = { ...progress.peakMetrics };
  const metricVersions = { ...progress.metricVersions };

  if (effect.mode === "absolute") {
    if (!Number.isSafeInteger(effect.version) || effect.version < 0) {
      throw new TypeError("Absolute achievement effects require a safe version.");
    }
    const previousVersion = metricVersions[effect.metric] ?? -1;
    if (effect.version <= previousVersion) {
      return {
        progress,
        stale: true,
        newVerifiedTitleIds: [],
        newDisplayTitleIds: [],
      };
    }
    verifiedMetrics[effect.metric] = safeNonNegativeInteger(
      effect.value,
      Number.NaN,
    );
    if (!Number.isSafeInteger(verifiedMetrics[effect.metric])) {
      throw new TypeError("Absolute achievement values must be non-negative integers.");
    }
    metricVersions[effect.metric] = effect.version;
  } else if (effect.mode === "increment") {
    if (!Number.isSafeInteger(effect.delta) || effect.delta <= 0) {
      throw new TypeError("Achievement increments must be positive safe integers.");
    }
    verifiedMetrics[effect.metric] = addWithoutOverflow(
      verifiedMetrics[effect.metric],
      effect.delta,
    );
  } else {
    throw new TypeError("Achievement effect mode must be increment or absolute.");
  }

  if (effect.metric === "voiceSeconds") {
    verifiedMetrics.voiceMinutes = Math.floor(verifiedMetrics.voiceSeconds / 60);
  } else if (effect.metric === "hostSeconds") {
    verifiedMetrics.hostMinutes = Math.floor(verifiedMetrics.hostSeconds / 60);
  }
  for (const metric of catalog.metrics) {
    peakMetrics[metric] = Math.max(
      peakMetrics[metric],
      verifiedMetrics[metric],
    );
  }

  const verifiedIds = new Set(progress.verifiedUnlockedTitleIds);
  const verifiedTimestamps = {
    ...progress.verifiedUnlockedTitleTimestamps,
  };
  const newVerifiedTitleIds = [];
  for (const definition of catalog.definitions) {
    if (peakMetrics[definition.metric] < definition.threshold ||
        verifiedIds.has(definition.id)) {
      continue;
    }
    verifiedIds.add(definition.id);
    verifiedTimestamps[definition.id] = processedAt;
    newVerifiedTitleIds.push(definition.id);
  }

  progress.verifiedMetrics = verifiedMetrics;
  progress.peakMetrics = peakMetrics;
  progress.metricVersions = metricVersions;
  progress.verifiedUnlockedTitleIds = catalog.definitions
    .map((definition) => definition.id)
    .filter((id) => verifiedIds.has(id));
  progress.verifiedUnlockedTitleTimestamps = verifiedTimestamps;
  const newDisplayTitleIds = newVerifiedTitleIds.filter(
    (id) => !beforeDisplay.has(id),
  );

  return {
    progress,
    stale: false,
    newVerifiedTitleIds,
    newDisplayTitleIds,
  };
}

function metricDisplayValue(progress, metric) {
  // The historical flat counters were client-authoritative. Project only the
  // server-verified value; the legacy floor is retained privately for audit.
  return safeNonNegativeInteger(progress.verifiedMetrics[metric]);
}

function buildUserAchievementProjection(rawProgress, processedAt) {
  const progress = normalizeProgress(rawProgress);
  const projection = {};
  for (const [metric, field] of Object.entries(METRIC_TO_USER_FIELD)) {
    projection[field] = metricDisplayValue(progress, metric);
  }
  projection.unlockedTitleIds = availableTitleIds(progress);
  projection.unlockedTitleTimestamps = displayUnlockTimestamps(progress);
  projection.selectedTitleId = progress.selectedTitleId;
  projection.achievementsUpdatedAt = processedAt;
  projection.achievementSchemaVersion = ACHIEVEMENT_SCHEMA_VERSION;
  projection.achievementCatalogVersion = catalog.catalogVersion;
  return projection;
}

module.exports = {
  ACHIEVEMENT_SCHEMA_VERSION,
  ALL_COUNTER_METRICS,
  INTERNAL_METRICS,
  METRIC_TO_USER_FIELD,
  addWithoutOverflow,
  applyAchievementEffect,
  availableTitleIds,
  buildUserAchievementProjection,
  displayUnlockTimestamps,
  isTimestampLike,
  legacyProgressFromUser,
  metricDisplayValue,
  normalizeProgress,
  normalizeTitleIds,
  safeNonNegativeInteger,
};
