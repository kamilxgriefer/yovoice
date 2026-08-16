const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const {
  catalog,
  validateAndExpandCatalog,
} = require("../achievements/catalog");

function integerList(source) {
  return [...source.matchAll(/\d+/gu)].map((match) => Number(match[0]));
}

function quotedList(source) {
  return [...source.matchAll(/'([^']+)'/gu)].map((match) => match[1]);
}

function dartDefinitions() {
  const source = readFileSync(path.join(
    __dirname,
    "../../lib/features/achievements/data/achievement_catalog.dart",
  ), "utf8");
  const thresholds = integerList(
    source.match(/static const List<int> _thresholds = \[([\s\S]*?)\];/u)[1],
  );
  const rarities = [...source
    .match(/static const List<AchievementRarity> _rarities = \[([\s\S]*?)\];/u)[1]
    .matchAll(/AchievementRarity\.([A-Za-z]+)/gu)]
    .map((match) => match[1]);
  const definitions = [];
  const tracks = source.matchAll(
    /\.\.\._track\(\s*metric: '([^']+)',\s*descriptionNoun: '([^']+)',\s*(?:thresholds: const \[([^\]]+)\],\s*)?titles: const \[([\s\S]*?)\],\s*\),/gu,
  );
  for (const match of tracks) {
    const metric = match[1];
    const descriptionNoun = match[2];
    const trackThresholds = match[3] ? integerList(match[3]) : thresholds;
    const titles = quotedList(match[4]);
    for (let index = 0; index < titles.length; index += 1) {
      const threshold = trackThresholds[index];
      definitions.push({
        id: `${metric}_${threshold}`,
        title: titles[index],
        description: `Reach ${threshold} ${descriptionNoun}.`,
        metric,
        threshold,
        rarity: rarities[index],
      });
    }
  }
  return definitions;
}

test("server catalog is a 100-title byte-for-byte semantic mirror of Dart", () => {
  const server = catalog.definitions.map(({ xp: _, ...definition }) => definition);
  assert.equal(server.length, 100);
  assert.equal(new Set(server.map((item) => item.id)).size, 100);
  assert.deepEqual(server, dartDefinitions());
});

test("rarity XP parity yields the existing 18,900 XP total", () => {
  assert.equal(
    catalog.definitions.reduce((total, achievement) => total + achievement.xp, 0),
    18900,
  );
});

test("catalog validator rejects duplicate metrics and malformed thresholds", () => {
  const raw = require("../achievements/catalog.v1.json");
  const duplicate = structuredClone(raw);
  duplicate.tracks[1].metric = duplicate.tracks[0].metric;
  assert.throws(() => validateAndExpandCatalog(duplicate), /Duplicate achievement metric/u);

  const malformed = structuredClone(raw);
  malformed.tracks[0].thresholds = [1, 1, 2, 3, 4, 5, 6, 7, 8, 9];
  assert.throws(() => validateAndExpandCatalog(malformed), /strictly increasing/u);
});
