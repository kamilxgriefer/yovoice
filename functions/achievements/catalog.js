const rawCatalog = require("./catalog.v1.json");

const ALLOWED_RARITIES = new Set([
  "common",
  "uncommon",
  "rare",
  "epic",
  "legendary",
  "mythic",
]);

function requireNonEmptyString(value, label) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${label} must be a non-empty string.`);
  }
  return value.trim();
}

function requirePositiveThresholds(values, label) {
  if (!Array.isArray(values) || values.length !== 10) {
    throw new Error(`${label} must contain exactly ten thresholds.`);
  }
  let previous = 0;
  return values.map((value) => {
    if (!Number.isSafeInteger(value) || value <= previous) {
      throw new Error(`${label} must be strictly increasing positive integers.`);
    }
    previous = value;
    return value;
  });
}

function validateAndExpandCatalog(input) {
  if (!input || input.schemaVersion !== 1) {
    throw new Error("Unsupported achievement catalog schema.");
  }
  const catalogVersion = requireNonEmptyString(
    input.catalogVersion,
    "catalogVersion",
  );
  const defaultThresholds = requirePositiveThresholds(
    input.defaultThresholds,
    "defaultThresholds",
  );
  if (!Array.isArray(input.rarities) || input.rarities.length !== 10) {
    throw new Error("rarities must contain exactly ten entries.");
  }
  const rarities = input.rarities.map((rarity) => {
    if (!ALLOWED_RARITIES.has(rarity)) {
      throw new Error(`Unknown achievement rarity: ${rarity}.`);
    }
    return rarity;
  });
  for (const rarity of ALLOWED_RARITIES) {
    if (!Number.isSafeInteger(input.xpByRarity?.[rarity]) ||
        input.xpByRarity[rarity] <= 0) {
      throw new Error(`Missing positive XP value for ${rarity}.`);
    }
  }
  if (!Array.isArray(input.tracks) || input.tracks.length !== 10) {
    throw new Error("The achievement catalog must contain exactly ten tracks.");
  }

  const metrics = new Set();
  const ids = new Set();
  const definitions = [];
  for (const track of input.tracks) {
    const metric = requireNonEmptyString(track.metric, "track.metric");
    const descriptionNoun = requireNonEmptyString(
      track.descriptionNoun,
      `${metric}.descriptionNoun`,
    );
    if (metrics.has(metric)) {
      throw new Error(`Duplicate achievement metric: ${metric}.`);
    }
    metrics.add(metric);
    if (!Array.isArray(track.titles) || track.titles.length !== 10) {
      throw new Error(`${metric}.titles must contain exactly ten entries.`);
    }
    const thresholds = track.thresholds === undefined
      ? defaultThresholds
      : requirePositiveThresholds(track.thresholds, `${metric}.thresholds`);

    for (let index = 0; index < 10; index += 1) {
      const title = requireNonEmptyString(
        track.titles[index],
        `${metric}.titles[${index}]`,
      );
      const threshold = thresholds[index];
      const id = `${metric}_${threshold}`;
      if (ids.has(id)) throw new Error(`Duplicate achievement id: ${id}.`);
      ids.add(id);
      definitions.push(Object.freeze({
        id,
        title,
        description: `Reach ${threshold} ${descriptionNoun}.`,
        metric,
        threshold,
        rarity: rarities[index],
        xp: input.xpByRarity[rarities[index]],
      }));
    }
  }
  if (definitions.length !== 100) {
    throw new Error("The achievement catalog must expand to exactly 100 titles.");
  }

  return Object.freeze({
    schemaVersion: input.schemaVersion,
    catalogVersion,
    definitions: Object.freeze(definitions),
    metrics: Object.freeze([...metrics]),
    xpByRarity: Object.freeze({ ...input.xpByRarity }),
  });
}

const catalog = validateAndExpandCatalog(rawCatalog);
const definitionsById = new Map(
  catalog.definitions.map((definition) => [definition.id, definition]),
);
const definitionsByMetric = new Map(
  catalog.metrics.map((metric) => [
    metric,
    Object.freeze(
      catalog.definitions.filter((definition) => definition.metric === metric),
    ),
  ]),
);

function achievementById(id) {
  return definitionsById.get(id) ?? null;
}

function achievementsForMetric(metric) {
  return definitionsByMetric.get(metric) ?? Object.freeze([]);
}

module.exports = {
  ALLOWED_RARITIES,
  achievementById,
  achievementsForMetric,
  catalog,
  validateAndExpandCatalog,
};
