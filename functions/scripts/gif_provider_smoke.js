#!/usr/bin/env node
// Step 3 of the GIF activation checklist (docs/DEPLOYMENT.md).
//
// It proves the three things no test can prove without a real key, and that
// the whole design rests on:
//
//   1. the key works;
//   2. `rating=g` is honoured — every asset the live API returns for a
//      deliberately edgy query really is rated `g`;
//   3. THE PINNED CDN URL TEMPLATE ACTUALLY SERVES A 200 image/gif.
//
// (3) checks actual delivery of the rendition pinned by the server resolver.
// Client message creation remains denied in Rules; a missing CDN rendition
// means rendering is unverified, not that Rules rejected a legitimate send.
// Run this BEFORE flipping GIF_PROVIDER to giphy.
//
// Usage:
//   GIPHY_API_KEY=... node functions/scripts/gif_provider_smoke.js
//   GIPHY_API_KEY=... node functions/scripts/gif_provider_smoke.js "kotek"
//
// It reads and writes nothing: no Firestore, no Admin SDK, no emulator.

"use strict";

process.env.NODE_ENV = process.env.NODE_ENV || "test";

const { createGiphyProvider } = require("../media/gif/giphy_provider");
const { GIF_RATING, gifCdnUrl, isPinnedGifUrl } = require("../media/gif/gif_ref");

const QUERIES = process.argv.slice(2);
const SAMPLE_QUERIES = QUERIES.length > 0 ? QUERIES : ["cat", "kotek", "party"];
const HEAD_SAMPLE_SIZE = 5;

function line(symbol, message) {
  process.stdout.write(`${symbol} ${message}\n`);
}

async function headAsset(url) {
  const response = await fetch(url, { method: "HEAD", redirect: "follow" });
  return {
    status: response.status,
    contentType: response.headers.get("content-type") ?? "",
  };
}

async function main() {
  const apiKey = (process.env.GIPHY_API_KEY ?? "").trim();
  if (apiKey.length === 0) {
    line("✗", "GIPHY_API_KEY is not set. Export it and run again.");
    process.exitCode = 1;
    return;
  }

  const provider = createGiphyProvider({ apiKey });
  let failures = 0;
  const sampled = [];

  // 1 + 2 — the key works, and every returned asset really is rated g.
  for (const query of SAMPLE_QUERIES) {
    let page;
    try {
      page = await provider.search({ query, locale: "en", limit: 20 });
    } catch (error) {
      line("✗", `search("${query}") failed: ${error.code ?? error.message}`);
      failures += 1;
      continue;
    }
    const offRating = page.items.filter((item) => item.rating !== GIF_RATING);
    if (offRating.length > 0) {
      line(
        "✗",
        `search("${query}") returned ${offRating.length} asset(s) not rated ` +
          `${GIF_RATING}: ${offRating.map((item) => item.id).join(", ")}. ` +
          "The response re-filter would drop them, but the provider's rating " +
          "parameter is not being honoured — investigate before enabling.",
      );
      failures += 1;
    } else {
      line("✓", `search("${query}") -> ${page.items.length} assets, all rated ${GIF_RATING}`);
    }
    sampled.push(...page.items.slice(0, 2));
  }

  if (sampled.length === 0) {
    line("✗", "No assets sampled; cannot verify the URL pin.");
    process.exitCode = 1;
    return;
  }

  // 3 — the pin. This is the gate on the whole rules design.
  line("·", "Verifying the pinned CDN template against live assets…");
  const toCheck = sampled.slice(0, HEAD_SAMPLE_SIZE);
  for (const asset of toCheck) {
    const expected = gifCdnUrl("giphy", asset.id);
    if (!isPinnedGifUrl("giphy", asset.id, asset.full.url)) {
      line("✗", `${asset.id}: adapter produced ${asset.full.url}, expected ${expected}`);
      failures += 1;
      continue;
    }
    let head;
    try {
      head = await headAsset(expected);
    } catch (error) {
      line("✗", `${asset.id}: HEAD ${expected} threw ${error.message}`);
      failures += 1;
      continue;
    }
    const servesGif =
      head.status === 200 && head.contentType.toLowerCase().startsWith("image/");
    if (!servesGif) {
      line(
        "✗",
        `${asset.id}: HEAD ${expected} -> ${head.status} ${head.contentType}. ` +
          "DO NOT ENABLE THE PROVIDER: pinned-rendition delivery is unverified. " +
          "Investigate the adapter and CDN rendition under review, then rerun " +
          "this gate. Do not weaken message Rules or bypass the URL pin.",
      );
      failures += 1;
    } else {
      line("✓", `${asset.id}: ${expected} -> ${head.status} ${head.contentType}`);
    }
  }

  // Attribution is contractual, so say it out loud rather than assuming the
  // reader remembers.
  line("·", `Attribution required: "${provider.attribution.text}" must be visible in the picker.`);

  if (failures > 0) {
    line("✗", `${failures} check(s) failed. Do NOT set GIF_PROVIDER=giphy yet.`);
    process.exitCode = 1;
    return;
  }
  line("✓", "All checks passed. Deploy firestore.rules first, then functions.");
}

main().catch((error) => {
  line("✗", `Unexpected failure: ${error?.stack ?? error}`);
  process.exitCode = 1;
});
