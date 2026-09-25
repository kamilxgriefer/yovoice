// In-app bug reports: optional alert channels.
//
// A report is complete the moment it is written: it is listed in the Staff
// Center (Bug reports), which needs nothing but the existing
// YOVOICE_PROTECTED_OWNER_UID secret. The channels below only ANNOUNCE it, and
// each is off twice over:
//
//   1. SOURCE-GATED in functions/index.js. While both gates are off the
//      delivery trigger is not exported at all and no secret is declared, so
//      `firebase deploy` never asks for one (the GIPHY pattern, ADR-214).
//   2. RUNTIME-SWITCHED in the Admin-only appConfig/bugReports document:
//      `emailEnabled` + `emailTo` + `emailFrom`, and `githubEnabled` +
//      `githubRepo`. The recipient and sender addresses live there and not in
//      functions/.env, because functions/.env is committed to a public
//      repository.
//
// Both channels are LINK-ONLY. An alert carries the report id, the platform,
// the app version and build, the screen name and whether a screenshot was
// requested or attached — and nothing the reporter wrote or showed: no
// description, no uid, no screenshot, no OS version, no locale. The report
// itself stays in Firebase, where the 180-day sweep, the owner's delete
// action and account deletion all reach it. A copy in a mailbox, in Resend's
// sent-mail log or in a GitHub issue is reached by none of those, so no copy
// of the reporter's words or image is ever made there (the privacy text in
// docs/SECURITY.md promises exactly this). The owner reads the report in the
// Staff Center, looking it up by the id in the alert.
//
// E-mail goes through the Resend HTTP API with the RESEND_API_KEY secret. The
// only Resend use in this project before this was Firebase Auth's own SMTP
// relay, configured in the Firebase console (ADR-008); Cloud Functions held no
// Resend credential, so this is a new, separately scoped key.
//
// GitHub opens an issue with the GITHUB_BUG_REPORT_TOKEN secret, as the route
// to "a new Claude chat" (a Claude Code routine or action that reacts to new
// issues). kamilxgriefer/yovoice is PUBLIC; since the issue is link-only it is
// the same minimal issue whatever the repository's visibility. The retired
// `githubIncludeDescription` switch is ignored if it is still set.
//
// Each channel has its own project-wide daily budget (RATE_LIMITS in
// contract.js). A report over budget is still stored and listed; it is only
// not announced, and its channel records "throttled".

const { consumeRateLimit, rateLimitReference } = require("../integrity/guards");
const {
  BUG_REPORTS,
  BUG_REPORT_CONFIG,
  GLOBAL_RATE_LIMIT_SENTINEL,
  RATE_LIMITS,
  REPORT_ID_PATTERN,
} = require("./contract");

const MAX_ATTEMPTS = 5;
const CLAIM_LEASE_MS = 5 * 60 * 1000;
// A stalled provider must fail the attempt well inside the trigger's 60 s.
const PROVIDER_TIMEOUT_MS = 15 * 1000;
const CHANNEL_BUDGETS = Object.freeze({
  email: RATE_LIMITS.emailDelivery,
  github: RATE_LIMITS.githubDelivery,
});
const REPOSITORY_PATTERN = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\/[A-Za-z0-9._-]{1,100}$/u;
const EMAIL_PATTERN = /^[^\s@<>"',;]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24}$/u;
// "YO Voice Bugs <bugs@yovoice.app>" or a bare address.
const SENDER_PATTERN = /^(?:[A-Za-z0-9 ._-]{1,64} <[^\s@<>"',;]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24}>|[^\s@<>"',;]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24})$/u;

const CHANNELS = Object.freeze(["email", "github"]);

class DeliveryFailure extends Error {
  constructor(code) {
    super(`Bug report delivery failed: ${code}`);
    this.code = code;
  }
}

function timeoutSignal() {
  return typeof AbortSignal !== "undefined" && typeof AbortSignal.timeout === "function"
    ? AbortSignal.timeout(PROVIDER_TIMEOUT_MS)
    : undefined;
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/gu, "&amp;")
    .replace(/</gu, "&lt;")
    .replace(/>/gu, "&gt;")
    .replace(/"/gu, "&quot;")
    .replace(/'/gu, "&#39;");
}

// The only context an alert carries. Every value is server-validated against
// a strict pattern or enum in contract.js before it is stored.
function contextOf(report) {
  const context = report?.context ?? {};
  const text = (value) => (typeof value === "string" ? value : "unknown");
  return {
    platform: text(context.platform),
    appVersion: text(context.appVersion),
    buildNumber: text(context.buildNumber),
    route: text(context.route),
  };
}

/**
 * What the alert says about the screenshot. The trigger fires when the report
 * is created, before any upload, so "reserved" means requested, not attached.
 */
function screenshotLine(report) {
  switch (report?.screenshot?.status) {
    case "attached": return "attached (open it in the Staff Center)";
    case "reserved": return "requested (upload pending)";
    default: return "no";
  }
}

/** The link-only alert e-mail: no description, no uid, no screenshot. */
function buildBugReportEmail(reportId, report) {
  const context = contextOf(report);
  const lines = [
    `Report: ${reportId}`,
    `App: ${context.appVersion} (${context.buildNumber}) on ${context.platform}`,
    `Screen: ${context.route}`,
    `Screenshot: ${screenshotLine(report)}`,
  ];
  const footer = "Read the report in YO Voice > Staff Center > Bug reports (owner only); " +
    "look it up by its id. This e-mail never contains the description, the reporter " +
    "or the screenshot.";
  return {
    subject: `[YO Voice bug] ${context.platform} ${context.appVersion}+${context.buildNumber} · ${reportId}`,
    text: `A new in-app bug report arrived.\n\n${lines.join("\n")}\n\n${footer}\n`,
    html: [
      "<div style=\"font-family:system-ui,sans-serif;font-size:14px;line-height:1.5\">",
      "<p>A new in-app bug report arrived.</p>",
      `<p>${lines.map(escapeHtml).join("<br>")}</p>`,
      `<p style="color:gray">${escapeHtml(footer)}</p>`,
      "</div>",
    ].join(""),
  };
}

/** The link-only GitHub issue, identical for a public and a private repository. */
function buildBugReportIssue(reportId, report) {
  const context = contextOf(report);
  const lines = [
    "A new in-app bug report arrived.",
    "",
    `- Report: \`${reportId}\``,
    `- App: ${context.appVersion} (${context.buildNumber}) on ${context.platform}`,
    `- Screen: \`${context.route}\``,
    `- Screenshot: ${screenshotLine(report)}`,
    "",
    "The description, the reporter and any screenshot are in YO Voice > Staff Center > " +
      "Bug reports (owner only). Look the report up by its id.",
  ];
  return {
    title: `Bug report ${reportId} (${context.platform} ${context.appVersion}+${context.buildNumber})`,
    body: lines.join("\n"),
  };
}

function readConfig(snapshot) {
  const value = snapshot?.exists ? snapshot.data() ?? {} : {};
  const emailTo = typeof value.emailTo === "string" ? value.emailTo.trim() : "";
  const emailFrom = typeof value.emailFrom === "string" ? value.emailFrom.trim() : "";
  const githubRepo = typeof value.githubRepo === "string" ? value.githubRepo.trim() : "";
  return {
    email: value.emailEnabled === true && EMAIL_PATTERN.test(emailTo) && SENDER_PATTERN.test(emailFrom)
      ? { emailTo, emailFrom }
      : null,
    github: value.githubEnabled === true && REPOSITORY_PATTERN.test(githubRepo)
      ? { githubRepo }
      : null,
  };
}

/**
 * @param {object} dependencies
 * @param {object} dependencies.channels  { email?: { apiKey: () => string },
 *                                          github?: { token: () => string } }
 *                                        — a channel absent here is source-gated off.
 */
function createBugReportDelivery(dependencies) {
  const {
    db, Timestamp, fetchImpl = globalThis.fetch, clock = Date.now, logger = console,
    channels = {},
  } = dependencies ?? {};
  if (!db?.runTransaction || !Timestamp?.fromMillis || typeof fetchImpl !== "function") {
    throw new TypeError("db, Timestamp and fetch are required.");
  }
  const reportRef = (reportId) => db.collection(BUG_REPORTS).doc(reportId);

  async function setDelivery(reportId, channel, value) {
    await reportRef(reportId).update({ [`delivery.${channel}`]: value });
  }

  /**
   * One transactional claim per channel:
   *   { state: "done" }     nothing to do (sent, failed, throttled, gone)
   *   { state: "leased" }   another attempt holds a live lease; the caller
   *                         THROWS so the event is retried after the lease,
   *                         never silently counted as delivered
   *   { state: "claimed", report, attempts }
   */
  async function claim(reportId, channel) {
    const budget = CHANNEL_BUDGETS[channel];
    const budgetRef = rateLimitReference(db, budget.scope, GLOBAL_RATE_LIMIT_SENTINEL);
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reportRef(reportId));
      if (!snapshot.exists) return { state: "done" };
      const report = snapshot.data() ?? {};
      const entry = report.delivery?.[channel] ?? {};
      const nowMs = clock();
      if (entry.status === "sent" || entry.status === "failed" || entry.status === "throttled") {
        return { state: "done" };
      }
      if (entry.status === "sending" && typeof entry.claimedAt?.toMillis === "function" &&
          nowMs - entry.claimedAt.toMillis() < CLAIM_LEASE_MS) {
        return { state: "leased" };
      }
      const attempts = (Number.isSafeInteger(entry.attempts) ? entry.attempts : 0) + 1;
      if (attempts > MAX_ATTEMPTS) {
        transaction.update(reportRef(reportId), {
          [`delivery.${channel}`]: {
            ...entry, status: "failed", updatedAt: Timestamp.fromMillis(nowMs),
          },
        });
        return { state: "done" };
      }
      const budgetSnapshot = await transaction.get(budgetRef);
      try {
        consumeRateLimit(transaction, budgetSnapshot, {
          reference: budgetRef,
          scope: budget.scope,
          uid: GLOBAL_RATE_LIMIT_SENTINEL,
          nowMs,
          now: Timestamp.fromMillis(nowMs),
          maxEvents: budget.maxEvents,
          windowMs: budget.windowMs,
        });
      } catch (error) {
        if (error?.code !== "resource-exhausted") throw error;
        // Over the channel's daily budget: stored and listed, not announced.
        transaction.update(reportRef(reportId), {
          [`delivery.${channel}`]: {
            status: "throttled",
            attempts: attempts - 1,
            lastErrorCode: "budget",
            updatedAt: Timestamp.fromMillis(nowMs),
          },
        });
        return { state: "throttled" };
      }
      transaction.update(reportRef(reportId), {
        [`delivery.${channel}`]: {
          status: "sending",
          attempts,
          claimedAt: Timestamp.fromMillis(nowMs),
          lastErrorCode: typeof entry.lastErrorCode === "string" ? entry.lastErrorCode : null,
        },
      });
      return { state: "claimed", report, attempts };
    });
  }

  async function sendEmail(reportId, report, config) {
    const email = buildBugReportEmail(reportId, report);
    let response;
    try {
      response = await fetchImpl("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${channels.email.apiKey()}`,
          "Content-Type": "application/json",
          "Idempotency-Key": `yovoice-bug-${reportId}`,
        },
        signal: timeoutSignal(),
        body: JSON.stringify({
          from: config.emailFrom,
          to: [config.emailTo],
          subject: email.subject,
          text: email.text,
          html: email.html,
        }),
      });
    } catch (_) {
      throw new DeliveryFailure("network");
    }
    if (!response.ok) throw new DeliveryFailure(`http-${response.status}`);
    const body = await response.json().catch(() => ({}));
    return typeof body?.id === "string" ? body.id.slice(0, 128) : null;
  }

  async function githubRequest(path, init = {}) {
    try {
      return await fetchImpl(`https://api.github.com${path}`, {
        ...init,
        signal: timeoutSignal(),
        headers: {
          Accept: "application/vnd.github+json",
          Authorization: `Bearer ${channels.github.token()}`,
          "X-GitHub-Api-Version": "2022-11-28",
          "User-Agent": "yovoice-bug-reports",
          ...(init.body ? { "Content-Type": "application/json" } : {}),
        },
      });
    } catch (_) {
      throw new DeliveryFailure("network");
    }
  }

  /**
   * GitHub has no idempotency key. On a retry (an earlier attempt may have
   * created the issue and lost the answer), look for an issue already titled
   * with this report id among the most recent ones before creating another.
   */
  async function existingIssue(reportId, config) {
    const response = await githubRequest(
      `/repos/${config.githubRepo}/issues?state=all&sort=created&direction=desc&per_page=100`);
    if (!response.ok) throw new DeliveryFailure(`http-${response.status}`);
    const issues = await response.json().catch(() => []);
    if (!Array.isArray(issues)) return null;
    const match = issues.find((issue) => typeof issue?.title === "string" &&
      issue.title.includes(reportId) && Number.isSafeInteger(issue.number));
    return match ? String(match.number) : null;
  }

  async function sendGithub(reportId, report, config, { attempts = 1 } = {}) {
    if (attempts > 1) {
      const found = await existingIssue(reportId, config);
      if (found !== null) return found;
    }
    const issue = buildBugReportIssue(reportId, report);
    const response = await githubRequest(`/repos/${config.githubRepo}/issues`, {
      method: "POST",
      body: JSON.stringify({ title: issue.title, body: issue.body }),
    });
    if (!response.ok) throw new DeliveryFailure(`http-${response.status}`);
    const body = await response.json().catch(() => ({}));
    return Number.isSafeInteger(body?.number) ? String(body.number) : null;
  }

  const SENDERS = Object.freeze({ email: sendEmail, github: sendGithub });

  /**
   * Announces one report on every source-enabled channel. Throws after
   * recording a retryable failure, so the trigger's retry delivers it again;
   * a channel that already sent is never sent twice.
   */
  async function deliverBugReport(reportId) {
    if (typeof reportId !== "string" || !REPORT_ID_PATTERN.test(reportId)) return { skipped: true };
    const config = readConfig(await db.collection(BUG_REPORT_CONFIG.collection)
      .doc(BUG_REPORT_CONFIG.id).get());
    const outcome = {};
    let retry = false;
    for (const channel of CHANNELS) {
      if (!channels[channel]) continue;
      if (!config[channel]) {
        await setDelivery(reportId, channel, {
          status: "disabled", updatedAt: Timestamp.fromMillis(clock()),
        });
        outcome[channel] = "disabled";
        continue;
      }
      const claimed = await claim(reportId, channel);
      if (claimed.state === "leased") {
        // Another attempt is (or was, until it died) sending. Retry the event
        // after the lease instead of reporting success for an alert that may
        // never have gone out.
        outcome[channel] = "leased";
        retry = true;
        continue;
      }
      if (claimed.state === "throttled") {
        outcome[channel] = "throttled";
        continue;
      }
      if (claimed.state !== "claimed") {
        outcome[channel] = "skipped";
        continue;
      }
      try {
        const externalId = await SENDERS[channel](reportId, claimed.report, config[channel], {
          attempts: claimed.attempts,
        });
        await setDelivery(reportId, channel, {
          status: "sent",
          attempts: claimed.attempts,
          sentAt: Timestamp.fromMillis(clock()),
          externalId,
          lastErrorCode: null,
        });
        outcome[channel] = "sent";
      } catch (error) {
        const code = error instanceof DeliveryFailure ? error.code : "internal";
        // A 4xx other than 408/429 will not heal by retrying: record it once.
        const permanent = /^http-4(?!08|29)[0-9]{2}$/u.test(code);
        await setDelivery(reportId, channel, {
          status: permanent ? "failed" : "retrying",
          attempts: claimed.attempts,
          lastErrorCode: code,
          updatedAt: Timestamp.fromMillis(clock()),
        });
        // Constants only: never the report text, never a credential.
        logger.warn?.("bug report delivery failed", { reportId, channel, code });
        outcome[channel] = permanent ? "failed" : "retrying";
        if (!permanent) retry = true;
      }
    }
    if (retry) {
      const error = new Error("Bug report delivery will be retried.");
      error.outcome = outcome;
      throw error;
    }
    return outcome;
  }

  return Object.freeze({ deliverBugReport });
}

module.exports = {
  CLAIM_LEASE_MS,
  MAX_ATTEMPTS,
  buildBugReportEmail,
  buildBugReportIssue,
  createBugReportDelivery,
  escapeHtml,
  readConfig,
};
