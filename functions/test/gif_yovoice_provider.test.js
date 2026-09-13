"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const {
  GIF_PROVIDERS,
  gifCdnUrl,
  isPinnedGifUrl,
} = require("../media/gif/gif_ref");
const { createGifProvider } = require("../media/gif/provider");
const {
  YOVOICE_ATTRIBUTION,
  YOVOICE_GIFS,
  createYovoiceGifProvider,
} = require("../media/gif/yovoice_provider");

test("YO Voice Originals are a real production provider with no credential", () => {
  const provider = createGifProvider({
    provider: GIF_PROVIDERS.yovoice,
    apiKey: "",
    env: {},
  });
  assert.equal(provider.id, GIF_PROVIDERS.yovoice);
  assert.equal(provider.isConfigured, true);
  assert.deepEqual(provider.attribution, YOVOICE_ATTRIBUTION);
});

test("every catalog id has one exact local asset pin", async () => {
  const provider = createYovoiceGifProvider({ now: () => 1234 });
  const page = await provider.trending({ limit: 30 });
  assert.equal(page.items.length, YOVOICE_GIFS.length);
  assert.equal(page.fetchedAt, 1234);
  for (const item of page.items) {
    const expected = `asset://yovoice/gifs/${item.id}.gif`;
    assert.equal(item.provider, GIF_PROVIDERS.yovoice);
    assert.equal(item.rating, "g");
    assert.equal(item.full.url, expected);
    assert.equal(item.preview.url, expected);
    assert.equal(gifCdnUrl(item.provider, item.id), expected);
    assert.ok(isPinnedGifUrl(item.provider, item.id, item.full.url));
  }
});

test("search is bilingual, conjunctive and paged", async () => {
  const provider = createYovoiceGifProvider();
  const polish = await provider.search({ query: "DZIĘKUJĘ", limit: 24 });
  assert.deepEqual(polish.items.map((item) => item.id), ["yoThx001"]);

  const love = await provider.search({ query: "MIŁOŚĆ", limit: 24 });
  assert.deepEqual(love.items.map((item) => item.id), ["yoLove01"]);

  const fire = await provider.search({ query: "ogień", limit: 24 });
  assert.deepEqual(fire.items.map((item) => item.id), ["yoFire01"]);

  const first = await provider.search({ query: "super", limit: 1 });
  assert.equal(first.items.length, 1);
  assert.equal(first.nextCursor, "1");
  const second = await provider.search({
    query: "super",
    limit: 1,
    cursor: first.nextCursor,
  });
  assert.equal(second.items.length, 1);
  assert.notEqual(second.items[0].id, first.items[0].id);
});

test("resolve returns only catalogued ids", async () => {
  const provider = createYovoiceGifProvider();
  assert.equal((await provider.resolve({ id: "yoLove01" })).items.length, 1);
  assert.deepEqual((await provider.resolve({ id: "../secret" })).items, []);
});

test("the provider catalog and committed Flutter asset manifest cannot drift", () => {
  const assetDirectory = path.resolve(
    __dirname,
    "../../assets/gifs/yovoice",
  );
  const manifest = JSON.parse(
    fs.readFileSync(path.join(assetDirectory, "manifest.json"), "utf8"),
  );
  assert.deepEqual(
    manifest.files.map((entry) => entry.id),
    YOVOICE_GIFS.map((entry) => entry[0]),
  );
  for (const entry of manifest.files) {
    const payload = fs.readFileSync(path.join(assetDirectory, entry.file));
    assert.equal(payload.subarray(0, 6).toString("ascii"), "GIF89a");
    assert.equal(payload.readUInt16LE(6), manifest.width);
    assert.equal(payload.readUInt16LE(8), manifest.height);
    assert.equal(payload.length, entry.bytes);
    assert.equal(
      crypto.createHash("sha256").update(payload).digest("hex"),
      entry.sha256,
    );
  }
});
