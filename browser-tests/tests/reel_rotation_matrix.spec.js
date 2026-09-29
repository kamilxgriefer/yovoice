// Chrome oracle for the Yeel "Obróć" rotation (ADR-235).
//
// The composer bakes a rotation into the tkhd matrix of each video track; web
// viewers then rely on the browser applying that matrix. This spec plays the
// committed goldens (made by the app's own patcher, test/fixtures/reels) in
// a bare <video> and checks what Chrome reports and draws:
//   * videoWidth/videoHeight swap for a quarter turn;
//   * the red top-left marker of the synthetic picture lands at TR / BR / BL
//     for one / two / three clockwise turns.
// The VP9 fMP4 golden always runs. H.264 needs proprietary codecs, which the
// Linux CI Chromium build lacks, so those cases skip where canPlayType says so.
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { expect, test } from "@playwright/test";

const here = path.dirname(fileURLToPath(import.meta.url));
const fixtures = path.join(here, "..", "..", "test", "fixtures", "reels");
// The Chromium MediaRecorder original is referenced in place, not copied.
const functionsFixtures = path.join(
  here,
  "..",
  "..",
  "functions",
  "test",
  "fixtures",
);

function fixturePath(name) {
  const file = path.basename(name);
  return file === "chromium_mediarecorder_fragmented.mp4"
    ? path.join(functionsFixtures, file)
    : path.join(fixtures, file);
}
const prefix = "/__reel_rotation__/";

async function openHarness(page) {
  await page.route(`**${prefix}**`, async (route) => {
    const name = decodeURIComponent(new URL(route.request().url()).pathname)
      .slice(prefix.length);
    if (name === "" || name === "index.html") {
      await route.fulfill({
        status: 200,
        contentType: "text/html",
        body: "<!doctype html><html><body></body></html>",
      });
      return;
    }
    const body = readFileSync(fixturePath(name));
    await route.fulfill({
      status: 200,
      contentType: name.endsWith(".mov") ? "video/quicktime" : "video/mp4",
      body,
    });
  });
  await page.goto(`${prefix}index.html`);
}

async function inspect(page, name) {
  return page.evaluate(async (src) => {
    const video = document.createElement("video");
    video.muted = true;
    video.src = src;
    document.body.appendChild(video);
    try {
      await new Promise((resolve, reject) => {
        video.onloadeddata = resolve;
        video.onerror = () =>
          reject(new Error(`media error ${video.error && video.error.code}`));
        setTimeout(() => reject(new Error("timeout")), 10000);
      });
    } catch (error) {
      return { error: error.message };
    }
    const canvas = document.createElement("canvas");
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const context = canvas.getContext("2d");
    context.drawImage(video, 0, 0);
    const red = (x, y) => {
      const [r, , b] = context.getImageData(x, y, 1, 1).data;
      return r > 150 && b < 80;
    };
    const w = canvas.width;
    const h = canvas.height;
    const quadrants = [
      ["TL", red((w / 4) | 0, (h / 4) | 0)],
      ["TR", red(((3 * w) / 4) | 0, (h / 4) | 0)],
      ["BL", red((w / 4) | 0, ((3 * h) / 4) | 0)],
      ["BR", red(((3 * w) / 4) | 0, ((3 * h) / 4) | 0)],
    ]
      .filter(([, hit]) => hit)
      .map(([quadrant]) => quadrant);
    video.remove();
    return { width: video.videoWidth, height: video.videoHeight, quadrants };
  }, `${prefix}${name}`);
}

test("a rotated VP9 fMP4 swaps its reported size", async ({ page }) => {
  await openHarness(page);
  const original = await inspect(page, "chromium_mediarecorder_fragmented.mp4");
  expect(original.error).toBeUndefined();
  expect({ width: original.width, height: original.height }).toEqual({
    width: 160,
    height: 120,
  });
  const rotated = await inspect(page, "chromium_mediarecorder_fragmented.rot1.mp4");
  expect(rotated.error).toBeUndefined();
  expect({ width: rotated.width, height: rotated.height }).toEqual({
    width: 120,
    height: 160,
  });
});

const h264 = [
  // [file, expected size, expected marker quadrant]
  ["reel_landscape_faststart.mp4", { width: 64, height: 36 }, "TL"],
  ["reel_landscape_faststart.rot1.mp4", { width: 36, height: 64 }, "TR"],
  ["reel_iphone_rot90.mov", { width: 36, height: 64 }, "TR"],
  ["reel_iphone_rot90.rot1.mov", { width: 64, height: 36 }, "BR"],
  ["reel_landscape_av_moovlast.rot3.mp4", { width: 36, height: 64 }, "BL"],
];

for (const [name, size, quadrant] of h264) {
  test(`H.264 ${name} plays ${size.width}x${size.height} with the marker at ${quadrant}`, async ({
    page,
  }) => {
    await openHarness(page);
    const playable = await page.evaluate(() =>
      document
        .createElement("video")
        .canPlayType('video/mp4; codecs="avc1.42E01E"'),
    );
    test.skip(playable === "", "This Chromium build has no H.264 decoder.");
    const result = await inspect(page, name);
    expect(result.error).toBeUndefined();
    expect({ width: result.width, height: result.height }).toEqual(size);
    expect(result.quadrants).toEqual([quadrant]);
  });
}
