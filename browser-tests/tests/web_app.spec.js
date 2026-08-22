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
  await expect(page.locator('meta[name="theme-color"]')).toHaveAttribute(
    "content",
    "#994BE7",
  );
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
