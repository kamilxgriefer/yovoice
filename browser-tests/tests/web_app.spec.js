import { expect, test } from "@playwright/test";

async function openCompiledApp(page) {
  await page.goto("/", { waitUntil: "domcontentloaded" });
  await expect(page).toHaveTitle(/YoVoice/i);

  const flutterRoot = page.locator("flutter-view, flt-glass-pane").first();
  await expect(flutterRoot).toBeVisible({ timeout: 90_000 });
  await expect(page.locator("#yovoice-bootstrap")).toHaveCount(0, {
    timeout: 90_000,
  });

  return flutterRoot;
}

test("the compiled Flutter web app boots with production metadata", async ({
  page,
}) => {
  const pageErrors = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));

  const flutterRoot = await openCompiledApp(page);

  await expect(flutterRoot).toBeVisible();
  // Flutter owns a second, runtime theme-color marker when SystemChrome
  // changes with Dark/Pearl. Keep the production HTML contract distinct from
  // that dynamic marker instead of relying on theme-color being globally
  // unique after the app has booted.
  const productionTheme = page.locator(
    'meta[name="theme-color"]:not(#flutterweb-theme)',
  );
  await expect(productionTheme).toHaveCount(1);
  await expect(productionTheme).toHaveAttribute("content", "#994BE7");
  await expect(page.locator("#flutterweb-theme")).toHaveCount(1);
  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute(
    "href",
    /site\.webmanifest/,
  );

  const bodyBackground = await page.evaluate(
    () => window.getComputedStyle(document.body).backgroundColor,
  );
  expect(bodyBackground).toBe("rgb(13, 6, 24)");
  expect(pageErrors).toEqual([]);
});

test("the compiled app boots without horizontal overflow on a phone viewport", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const flutterRoot = await openCompiledApp(page);

  const metrics = await page.evaluate(() => {
    const root = document.querySelector("flutter-view, flt-glass-pane");
    const rect = root?.getBoundingClientRect();
    return {
      overflow: document.documentElement.scrollWidth - window.innerWidth,
      rootWidth: rect?.width ?? 0,
      rootHeight: rect?.height ?? 0,
    };
  });

  expect(metrics.overflow).toBeLessThanOrEqual(2);
  expect(metrics.rootWidth).toBeGreaterThanOrEqual(388);
  expect(metrics.rootHeight).toBeGreaterThanOrEqual(800);
  await expect(flutterRoot).toBeVisible();
});
