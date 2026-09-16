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
  'desktop-split-preview.html',
);
const framesDir = process.argv[2] ?? '/private/tmp/yovoice-auth-desktop-frames';
const reviewDir = process.argv[3] ?? '/private/tmp/yovoice-auth-desktop-review';
const poster = process.argv[4] ?? path.resolve(path.dirname(source), 'desktop-split-preview.png');

await fs.rm(framesDir, { recursive: true, force: true });
await fs.rm(reviewDir, { recursive: true, force: true });
await fs.mkdir(framesDir, { recursive: true });
await fs.mkdir(reviewDir, { recursive: true });

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({
  viewport: { width: 1440, height: 900 },
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
await page.waitForFunction(() => window.__desktopSplit?.ready === true);

const metadata = await page.evaluate(() => ({
  totalMs: window.__desktopSplit.totalMs,
  fps: window.__desktopSplit.fps,
  animationCount: document.getAnimations().length,
  viewport: { width: innerWidth, height: innerHeight },
  workspace: document.getElementById('workspace').getBoundingClientRect().toJSON(),
}));

const keyframes = [
  0,
  1160,
  1280,
  1400,
  1550,
  1780,
  1980,
  2160,
  3200,
  4460,
  4580,
  4700,
  4850,
  5080,
  5300,
  5460,
  6500,
  8967,
];

for (const ms of keyframes) {
  await page.evaluate(time => window.__desktopSplit.renderAt(time), ms);
  await page.screenshot({
    path: path.join(reviewDir, `review-${String(ms).padStart(4, '0')}ms.png`),
  });
}

await page.evaluate(() => window.__desktopSplit.renderAt(3200));
await page.screenshot({ path: poster });

const frameCount = Math.round((metadata.totalMs / 1000) * metadata.fps);
const frameMs = 1000 / metadata.fps;
for (let frame = 0; frame < frameCount; frame += 1) {
  await page.evaluate(time => window.__desktopSplit.renderAt(time), frame * frameMs);
  await page.screenshot({
    path: path.join(framesDir, `frame-${String(frame).padStart(3, '0')}.jpg`),
    type: 'jpeg',
    quality: 96,
  });
}

await page.evaluate(() => window.__desktopSplit.renderAt(0));
const start = await page.screenshot();
await page.evaluate(time => window.__desktopSplit.renderAt(time), metadata.totalMs);
const seam = await page.screenshot();

const loopStates = [];
for (const time of [0, frameMs, metadata.totalMs - frameMs]) {
  await page.evaluate(value => window.__desktopSplit.renderAt(value), time);
  loopStates.push(await page.evaluate(value => ({
    time: value,
    ambient: Number(document.getElementById('canvas').dataset.ambient),
    pageArcOne: Number.parseFloat(document.getElementById('pageArcOne').style.strokeDashoffset),
    pageArcTwo: Number.parseFloat(document.getElementById('pageArcTwo').style.strokeDashoffset),
    brandLineOne: Number.parseFloat(document.getElementById('brandLineOne').style.strokeDashoffset),
    brandLineTwo: Number.parseFloat(document.getElementById('brandLineTwo').style.strokeDashoffset),
  }), time));
}

const responsiveChecks = [];
for (const viewport of [
  { width: 1000, height: 700 },
  { width: 1180, height: 800 },
  { width: 1440, height: 900 },
]) {
  const qaPage = await browser.newPage({
    viewport,
    deviceScaleFactor: 1,
    colorScheme: 'dark',
    reducedMotion: 'reduce',
  });
  await qaPage.goto(pathToFileURL(source).href, { waitUntil: 'load' });
  await qaPage.waitForFunction(() => window.__desktopSplit?.ready === true);

  await qaPage.evaluate(() => window.__desktopSplit.renderAt(3200));
  const stable = await qaPage.evaluate(() => {
    const workspace = document.getElementById('workspace').getBoundingClientRect();
    const panel = document.getElementById('brandPanel').getBoundingClientRect();
    const registerForm = document.getElementById('registerForm').getBoundingClientRect();
    const registerZone = document.querySelector('.form-zone').getBoundingClientRect();
    const badge = document.querySelector('#registerForm .coming-soon').getBoundingClientRect();
    const copyElement = document.querySelector('#registerForm .provider.disabled .provider-copy');
    const copyRange = document.createRange();
    copyRange.selectNodeContents(copyElement);
    const providerCopy = copyRange.getBoundingClientRect();
    const tolerance = 1;
    const badgeOverlapsCopy = !(
      badge.right <= providerCopy.left ||
      badge.left >= providerCopy.right ||
      badge.bottom <= providerCopy.top ||
      badge.top >= providerCopy.bottom
    );

    return {
      viewport: { width: innerWidth, height: innerHeight },
      workspace: workspace.toJSON(),
      panel: panel.toJSON(),
      registerForm: registerForm.toJSON(),
      registerZone: registerZone.toJSON(),
      paneWidth: workspace.width / 2,
      panelInsideWorkspace:
        panel.left >= workspace.left - tolerance &&
        panel.right <= workspace.right + tolerance &&
        panel.top >= workspace.top - tolerance &&
        panel.bottom <= workspace.bottom + tolerance,
      formHorizontallyInsidePane:
        registerForm.left >= registerZone.left - tolerance &&
        registerForm.right <= registerZone.right + tolerance,
      badgeOverlapsCopy,
    };
  });

  const cover = [];
  for (const time of [1766.667, 1800, 5066.667, 5100]) {
    await qaPage.evaluate(value => window.__desktopSplit.renderAt(value), time);
    cover.push(await qaPage.evaluate(value => {
      const workspace = document.getElementById('workspace').getBoundingClientRect();
      const panel = document.getElementById('brandPanel').getBoundingClientRect();
      return {
        time: value,
        coverRatio: panel.width / workspace.width,
        leftGap: panel.left - workspace.left,
        rightGap: workspace.right - panel.right,
      };
    }, time));
  }

  responsiveChecks.push({ ...stable, cover });
  await qaPage.close();
}

await browser.close();

const identicalSeam = Buffer.compare(start, seam) === 0;
const cyclicDelta = (from, to, period) => {
  const raw = ((to - from + period / 2) % period + period) % period - period / 2;
  return raw;
};
const [loopStart, loopSecond, loopLast] = loopStates;
const loopContinuity = {
  ambientStepError: Math.abs(
    (loopStart.ambient - loopLast.ambient) -
    (loopSecond.ambient - loopStart.ambient)
  ),
  pageArcOneStepError: Math.abs(
    cyclicDelta(loopLast.pageArcOne, loopStart.pageArcOne, 25) -
    cyclicDelta(loopStart.pageArcOne, loopSecond.pageArcOne, 25)
  ),
  pageArcTwoStepError: Math.abs(
    cyclicDelta(loopLast.pageArcTwo, loopStart.pageArcTwo, 23) -
    cyclicDelta(loopStart.pageArcTwo, loopSecond.pageArcTwo, 23)
  ),
  brandLineOneStepError: Math.abs(
    cyclicDelta(loopLast.brandLineOne, loopStart.brandLineOne, 24) -
    cyclicDelta(loopStart.brandLineOne, loopSecond.brandLineOne, 24)
  ),
  brandLineTwoStepError: Math.abs(
    cyclicDelta(loopLast.brandLineTwo, loopStart.brandLineTwo, 21) -
    cyclicDelta(loopStart.brandLineTwo, loopSecond.brandLineTwo, 21)
  ),
};
const loopContinuityFailure = Object.values(loopContinuity).some(error => error > 1e-3);
const responsiveFailure = responsiveChecks.some(check =>
  check.paneWidth < 440 ||
  !check.panelInsideWorkspace ||
  !check.formHorizontallyInsidePane ||
  check.badgeOverlapsCopy ||
  check.cover.some(sample =>
    sample.coverRatio < .995 ||
    Math.abs(sample.leftGap) > 2 ||
    Math.abs(sample.rightGap) > 2
  )
);

const report = {
  source,
  framesDir,
  reviewDir,
  poster,
  frameCount,
  identicalSeam,
  loopStates,
  loopContinuity,
  errors,
  metadata,
  responsiveChecks,
};

await fs.writeFile(
  '/private/tmp/yovoice-auth-desktop-qa.json',
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));

if (
  !identicalSeam ||
  errors.length > 0 ||
  metadata.animationCount !== 0 ||
  loopContinuityFailure ||
  responsiveFailure
) {
  process.exitCode = 1;
}
