import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require(
  '/Users/kamil/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright',
);

const source = path.resolve(
  path.dirname(new URL(import.meta.url).pathname),
  'voice-curtain-preview.html',
);
const framesDir = process.argv[2] ?? '/private/tmp/yovoice-auth-curtain-frames';
const reviewDir = process.argv[3] ?? '/private/tmp/yovoice-auth-curtain-review';
const poster = process.argv[4] ?? path.resolve(path.dirname(source), 'voice-curtain-preview.png');

await fs.rm(framesDir, { recursive: true, force: true });
await fs.rm(reviewDir, { recursive: true, force: true });
await fs.mkdir(framesDir, { recursive: true });
await fs.mkdir(reviewDir, { recursive: true });

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({
  viewport: { width: 430, height: 844 },
  deviceScaleFactor: 1,
  colorScheme: 'dark',
  reducedMotion: 'no-preference',
});

const errors = [];
page.on('console', message => {
  if (message.type() === 'error') errors.push(`console: ${message.text()}`);
});
page.on('pageerror', error => errors.push(`pageerror: ${String(error)}`));

const url = `${pathToFileURL(source).href}?capture=1`;
await page.goto(url, { waitUntil: 'load' });
await page.waitForFunction(() => window.__voiceCurtain?.ready === true);

const metadata = await page.evaluate(() => ({
  totalMs: window.__voiceCurtain.totalMs,
  fps: window.__voiceCurtain.fps,
  animationCount: document.getAnimations().length,
  phone: document.getElementById('phone').getBoundingClientRect().toJSON(),
  card: document.getElementById('authCard').getBoundingClientRect().toJSON(),
}));

const keyframes = [0, 1133, 1300, 1467, 1667, 2600, 4367, 4533, 4700, 4933, 6000, 7967];
for (const ms of keyframes) {
  await page.evaluate(time => window.__voiceCurtain.renderAt(time), ms);
  await page.screenshot({
    path: path.join(reviewDir, `review-${String(ms).padStart(4, '0')}ms.png`),
  });
}

await page.evaluate(() => window.__voiceCurtain.renderAt(2600));
await page.screenshot({ path: poster });

const frameCount = Math.round((metadata.totalMs / 1000) * metadata.fps);
const frameMs = 1000 / metadata.fps;
for (let frame = 0; frame < frameCount; frame += 1) {
  await page.evaluate(time => window.__voiceCurtain.renderAt(time), frame * frameMs);
  await page.screenshot({
    path: path.join(framesDir, `frame-${String(frame).padStart(3, '0')}.jpg`),
    type: 'jpeg',
    quality: 96,
  });
}

await page.evaluate(() => window.__voiceCurtain.renderAt(0));
const start = await page.screenshot();
await page.evaluate(time => window.__voiceCurtain.renderAt(time), metadata.totalMs);
const seam = await page.screenshot();

const responsiveChecks = [];
for (const viewport of [
  { width: 320, height: 568 },
  { width: 390, height: 667 },
  { width: 430, height: 844 },
]) {
  const qaPage = await browser.newPage({
    viewport,
    deviceScaleFactor: 1,
    colorScheme: 'dark',
    reducedMotion: 'reduce',
  });
  await qaPage.goto(pathToFileURL(source).href, { waitUntil: 'load' });
  await qaPage.waitForFunction(() => window.__voiceCurtain?.ready === true);
  await qaPage.evaluate(() => window.__voiceCurtain.renderAt(2600));

  const check = await qaPage.evaluate(() => {
    const rect = id => document.getElementById(id).getBoundingClientRect().toJSON();
    const card = rect('authCard');
    const rail = rect('modeRail');
    const capsule = rect('curtain');
    const legal = document.querySelector('#registerView .legal').getBoundingClientRect().toJSON();
    const providerCopyElement = document.querySelector('#registerView .provider.disabled .provider-copy');
    const providerCopyRange = document.createRange();
    providerCopyRange.selectNodeContents(providerCopyElement);
    const providerCopy = providerCopyRange.getBoundingClientRect().toJSON();
    const badge = document.querySelector('#registerView .coming-soon').getBoundingClientRect().toJSON();
    const tolerance = 1;
    const badgeOverlapsCopy = !(
      badge.right <= providerCopy.left ||
      badge.left >= providerCopy.right ||
      badge.bottom <= providerCopy.top ||
      badge.top >= providerCopy.bottom
    );

    return {
      viewport: { width: innerWidth, height: innerHeight },
      bodyScrollHeight: document.body.scrollHeight,
      card,
      rail,
      capsule,
      legal,
      capsuleInsideRail:
        capsule.left >= rail.left - tolerance &&
        capsule.right <= rail.right + tolerance,
      contentInsideCard: legal.bottom <= card.bottom + tolerance,
      badgeOverlapsCopy,
    };
  });
  responsiveChecks.push(check);
  await qaPage.close();
}

await browser.close();

const identicalSeam = Buffer.compare(start, seam) === 0;
console.log(JSON.stringify({
  source,
  framesDir,
  reviewDir,
  poster,
  frameCount,
  identicalSeam,
  errors,
  metadata,
  responsiveChecks,
}, null, 2));

const responsiveFailure = responsiveChecks.some(check =>
  !check.capsuleInsideRail ||
  !check.contentInsideCard ||
  check.badgeOverlapsCopy ||
  check.bodyScrollHeight < check.viewport.height
);

if (
  !identicalSeam ||
  errors.length > 0 ||
  metadata.animationCount !== 0 ||
  responsiveFailure
) {
  process.exitCode = 1;
}
