const { logger } = require("firebase-functions/v2");
const { onSchedule } = require("firebase-functions/v2/scheduler");

// Keep-warm pinger (ADR-XXX, cost plan C3). It replaces `minInstances: 1` on
// the latency-critical callables: under request-based billing an idle Cloud
// Run instance above the minimum is not billed, and a request at least every
// ten minutes was measured to keep a min-0 instance alive (the 1-10 minute
// schedules had 1-4 instance starts in 8 days, all at deploys). Every five
// minutes this function sends each target ONE unauthenticated, empty callable
// request. Each target refuses it with HTTP 401 `unauthenticated` before any
// Firestore, Auth, Storage or LiveKit call (proved per target by
// test/keep_warm.test.js against the real export map), so a ping can never do
// work, and there is nothing to retry: the next tick is the retry.
//
// Warmth is best-effort. Cloud Run may still recycle an idle instance; the
// logged `ms` is the warmth monitor (a 401 slower than about 1.5 s was cold).

const REGION = "europe-west1";
const KEEP_WARM_FUNCTION_NAME = "keepWarmHotPathsSchedule";
const KEEP_WARM_SCHEDULE = "every 5 minutes";
const KEEP_WARM_PING_TIMEOUT_MS = 10_000;
// A stable User-Agent so Cloud Run request logs and any future 4xx-rate
// alert can exclude the pinger with one filter.
const KEEP_WARM_USER_AGENT = "yovoice-keepwarm";
// The smallest valid callable request. The callable wrapper error-logs a GET
// or a malformed body (firebase-functions lib/common/providers/https.js,
// isValidRequest), which would trip the "Backend ERROR logs" alert; a valid
// POST whose handler throws an HttpsError is not logged by the wrapper at all.
const KEEP_WARM_REQUEST_BODY = "{\"data\":null}";
const KEEP_WARM_LOG_MESSAGE = "keep-warm ping";

// Twelve hot paths, chosen from the cost plan (§2, §3 C3). Every one refuses
// an unauthenticated call before any I/O:
// - Direct messages (Stage B, integrity/stage_b_handlers.js authBoundRequest
//   -> requireActor): sendDirectMessage, openDirectConversation.
// - Direct calls (utils/auth.js requireAuthentication is the first statement
//   of startDirectCallHandler, transitionDirectCall and
//   createDirectCallTokenHandler): startDirectCall, acceptDirectCall,
//   createDirectCallToken.
// - Servers voice join (servers/registration.js callableHandler ->
//   authBoundRequest -> requireActor, before the activation-gate read):
//   startServerChannelSessionV1, createServerChannelTokenV1.
// - Servers text send (Stage B): sendClubMessage.
// - Reel publish (reels/index.js authBoundRequest -> requireActor):
//   reserveReelDraftV2, finalizeReelDraftV2.
// - Feeds: getVoiceMomentsFeedV2 (Stage B) and listReelsV2 (Reels).
const KEEP_WARM_TARGETS = Object.freeze([
  "sendDirectMessage",
  "openDirectConversation",
  "startDirectCall",
  "acceptDirectCall",
  "createDirectCallToken",
  "startServerChannelSessionV1",
  "createServerChannelTokenV1",
  "sendClubMessage",
  "reserveReelDraftV2",
  "finalizeReelDraftV2",
  "getVoiceMomentsFeedV2",
  "listReelsV2",
]);

const PROJECT_ID_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/u;

/**
 * The deployed project's id, read from the same sources the Admin SDK and the
 * repository's scripts read: GCLOUD_PROJECT, GOOGLE_CLOUD_PROJECT, then
 * FIREBASE_CONFIG.projectId (the Firebase CLI sets both on every deployed
 * function). Returns null when none holds a valid id.
 */
function resolveKeepWarmProjectId(env = process.env) {
  const candidates = [env.GCLOUD_PROJECT, env.GOOGLE_CLOUD_PROJECT];
  try {
    const config = JSON.parse(env.FIREBASE_CONFIG || "{}");
    candidates.push(config?.projectId);
  } catch (_) {
    // A malformed FIREBASE_CONFIG simply contributes no candidate.
  }
  for (const candidate of candidates) {
    if (typeof candidate === "string" && PROJECT_ID_PATTERN.test(candidate)) {
      return candidate;
    }
  }
  return null;
}

/**
 * The public callable URL, built exactly as the client SDKs build it for
 * `FirebaseFunctions.instanceFor(region: 'europe-west1')` and as
 * docs/DEPLOYMENT.md records the LiveKit webhook URL:
 * https://<region>-<projectId>.cloudfunctions.net/<name>.
 */
function keepWarmCallableUrl(projectId, name, region = REGION) {
  return `https://${region}-${projectId}.cloudfunctions.net/${name}`;
}

function classifyFailure(error) {
  const name = error?.name;
  return name === "TimeoutError" || name === "AbortError"
    ? "timeout"
    : "network-error";
}

/**
 * One ping. Never throws: a timeout, a network failure, a malformed response
 * or a synchronous fetch failure all become a status string.
 */
async function pingKeepWarmTarget(target, url, {
  fetchImpl,
  timeoutMs,
  now,
}) {
  const startedAt = now();
  let status;
  let response = null;
  try {
    response = await fetchImpl(url, {
      method: "POST",
      // Deliberately no Authorization and no App Check header.
      headers: {
        "content-type": "application/json",
        "user-agent": KEEP_WARM_USER_AGENT,
      },
      body: KEEP_WARM_REQUEST_BODY,
      redirect: "manual",
      signal: AbortSignal.timeout(timeoutMs),
    });
    status = Number.isSafeInteger(response?.status)
      ? response.status
      : "invalid-response";
  } catch (error) {
    status = classifyFailure(error);
  }
  const ms = Math.max(0, Math.round(now() - startedAt));
  // Release the connection; the few bytes of the 401 body are not needed.
  try {
    await response?.body?.cancel?.();
  } catch (_) {
    // Nothing to release.
  }
  return { target, status, ms };
}

function logInfo(log, message, fields) {
  try {
    log.info(message, fields);
  } catch (_) {
    // Logging must never turn a ping run into a failed Scheduler execution.
  }
}

/**
 * Pings every target in parallel and logs one INFO line per target:
 * { target, status, ms }. Never throws and never logs above INFO, so expected
 * 401s cannot reach the "Backend ERROR logs" alert (severity >= ERROR).
 */
async function pingKeepWarmTargets({
  targets = KEEP_WARM_TARGETS,
  env = process.env,
  fetchImpl = globalThis.fetch,
  log = logger,
  timeoutMs = KEEP_WARM_PING_TIMEOUT_MS,
  now = () => performance.now(),
  urlFor = null,
} = {}) {
  try {
    if (env.FUNCTIONS_EMULATOR === "true") {
      logInfo(log, "keep-warm skipped", { reason: "emulator" });
      return [];
    }
    let resolveUrl = urlFor;
    if (typeof resolveUrl !== "function") {
      const projectId = resolveKeepWarmProjectId(env);
      if (projectId === null) {
        logInfo(log, "keep-warm skipped", { reason: "no-project-id" });
        return [];
      }
      resolveUrl = (name) => keepWarmCallableUrl(projectId, name);
    }
    if (typeof fetchImpl !== "function") {
      logInfo(log, "keep-warm skipped", { reason: "no-fetch" });
      return [];
    }
    const settled = await Promise.allSettled(targets.map((target) =>
      pingKeepWarmTarget(target, resolveUrl(target), {
        fetchImpl,
        timeoutMs,
        now,
      })));
    const results = settled.map((outcome, index) => (
      outcome.status === "fulfilled"
        ? outcome.value
        : { target: targets[index], status: "network-error", ms: 0 }
    ));
    for (const result of results) {
      logInfo(log, KEEP_WARM_LOG_MESSAGE, {
        target: result.target,
        status: result.status,
        ms: result.ms,
      });
    }
    return results;
  } catch (error) {
    logInfo(log, "keep-warm skipped", {
      reason: "unexpected",
      name: typeof error?.name === "string" ? error.name.slice(0, 64) : "Error",
    });
    return [];
  }
}

const KEEP_WARM_SCHEDULE_OPTIONS = Object.freeze({
  region: REGION,
  schedule: KEEP_WARM_SCHEDULE,
  timeZone: "UTC",
  // A failed tick is never retried; the next tick five minutes later is.
  retryCount: 0,
  maxInstances: 1,
  memory: "256MiB",
  timeoutSeconds: 60,
});

// One-argument wrapper: the Scheduler event must never land in the
// dependency-injection parameter of pingKeepWarmTargets.
const keepWarmHotPathsSchedule = onSchedule(
  { ...KEEP_WARM_SCHEDULE_OPTIONS },
  async () => {
    await pingKeepWarmTargets();
  },
);

module.exports = {
  KEEP_WARM_FUNCTION_NAME,
  KEEP_WARM_LOG_MESSAGE,
  KEEP_WARM_PING_TIMEOUT_MS,
  KEEP_WARM_REQUEST_BODY,
  KEEP_WARM_SCHEDULE,
  KEEP_WARM_SCHEDULE_OPTIONS,
  KEEP_WARM_TARGETS,
  KEEP_WARM_USER_AGENT,
  keepWarmCallableUrl,
  keepWarmHotPathsSchedule,
  pingKeepWarmTarget,
  pingKeepWarmTargets,
  resolveKeepWarmProjectId,
};
