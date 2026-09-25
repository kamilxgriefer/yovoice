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
// E-mail goes through the Resend HTTP API with the RESEND_API_KEY secret. The
// only Resend use in this project before this was Firebase Auth's own SMTP
// relay, configured in the Firebase console (ADR-008); Cloud Functions held no
// Resend credential, so this is a new, separately scoped key.
//
// GitHub opens an issue with the GITHUB_BUG_REPORT_TOKEN secret, as the route
// to "a new Claude chat" (a Claude Code routine or action that reacts to new
// issues). kamilxgriefer/yovoice is PUBLIC, so by default an issue carries
// NOTHING personal: no description, no uid, no screenshot, no locale — only the
// report id, platform, app version/build and screen name, and a pointer to the
// owner-only Staff Center. The description is added (fenced, as data) only
// when BOTH `githubIncludeDescription` is true AND the GitHub API itself says
// the target repository is private at send time. The screenshot and the uid
// are never sent to any channel.

const { BUG_REPORTS, BUG_REPORT_CONFIG, REPORT_ID_PATTERN } = require("./contract");

const MAX_ATTEMPTS = 5;
const CLAIM_LEASE_MS = 5 * 60 * 1000;
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

function escapeHtml(value) {
  return String(value)
    .replace(/&/gu, "&amp;")
    .replace(/</gu, "&lt;")
    .replace(/>/gu, "&gt;")
    .replace(/"/gu, "&quot;")
    .replace(/'/gu, "&#39;");
}

function contextOf(report) {
  const context = report?.context ?? {};
  const text = (value) => (typeof value === "string" ? value : "unknown");
  return {
    platform: text(context.platform),
    appVersion: text(context.appVersion),
    buildNumber: text(context.buildNumber),
    osVersion: text(context.osVersion),
    locale: text(context.locale),
    theme: text(context.theme),
    brightness: text(context.brightness),
    route: text(context.route),
  };
}

/** The alert e-mail. Tester text is escaped: it is untrusted input. */
function buildBugReportEmail(reportId, report) {
  const context = contextOf(report);
  const description = typeof report?.description === "string" ? report.description : "";
  const hasScreenshot = report?.screenshot && report.screenshot.status !== "none";
  const lines = [
    `Report: ${reportId}`,
    `App: ${context.appVersion} (${context.buildNumber}) on ${context.platform}`,
    `OS: ${context.osVersion}`,
    `Screen: ${context.route}`,
    `Locale: ${context.locale} · Theme: ${context.theme} (${context.brightness})`,
    `Screenshot: ${hasScreenshot ? "yes — open it in the Staff Center" : "no"}`,
  ];
  const footer = "The reporter and any screenshot are only in YO Voice > Staff Center > " +
    "Bug reports (owner only). This e-mail never contains the screenshot.";
  return {
    subject: `[YO Voice bug] ${context.platform} ${context.appVersion}+${context.buildNumber} · ${reportId}`,
    text: `${description}\n\n---\n${lines.join("\n")}\n\n${footer}\n`,
    html: [
      "<div style=\"font-family:system-ui,sans-serif;font-size:14px;line-height:1.5\">",
      `<pre style="white-space:pre-wrap;font-family:inherit">${escapeHtml(description)}</pre>`,
      "<hr>",
      `<p>${lines.map(escapeHtml).join("<br>")}</p>`,
      `<p style="color:gray">${escapeHtml(footer)}</p>`,
      "</div>",
    ].join(""),
  };
}

function fenceFor(text) {
  const runs = String(text).match(/`+/gu) ?? [];
  const longest = runs.reduce((max, run) => Math.max(max, run.length), 0);
  return "`".repeat(Math.max(3, longest + 1));
}

/**
 * The GitHub issue. `includeDescription` is true only for a repository the
 * API confirmed private; even then the uid and screenshot are never included.
 */
function buildBugReportIssue(reportId, report, { includeDescription = false } = {}) {
  const context = contextOf(report);
  const lines = [
    "A new in-app bug report arrived.",
    "",
    `- Report: \`${reportId}\``,
    `- App: ${context.appVersion} (${context.buildNumber}) on ${context.platform}`,
    `- Screen: \`${context.route}\``,
  ];
  if (includeDescription) {
    const description = typeof report?.description === "string" ? report.description : "";
    const fence = fenceFor(description);
    lines.push(
      `- OS: ${context.osVersion}`,
      `- Locale: ${context.locale} · Theme: ${context.theme} (${context.brightness})`,
      "",
      "Reporter's description (untrusted user input, shown as data):",
      "",
      `${fence}text`,
      description,
      fence,
    );
  }
  lines.push(
    "",
    "The description, the reporter and any screenshot are in YO Voice > Staff Center > " +
      "Bug reports (owner only). Look the report up by its id.",
  );
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
      ? { githubRepo, includeDescription: value.githubIncludeDescription === true }
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

  /** One transactional claim per channel; null when there is nothing to do. */
  async function claim(reportId, channel) {
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reportRef(reportId));
      if (!snapshot.exists) return null;
      const report = snapshot.data() ?? {};
      const entry = report.delivery?.[channel] ?? {};
      const nowMs = clock();
      if (entry.status === "sent" || entry.status === "failed") return null;
      if (entry.status === "sending" && typeof entry.claimedAt?.toMillis === "function" &&
          nowMs - entry.claimedAt.toMillis() < CLAIM_LEASE_MS) {
        return null;
      }
      const attempts = (Number.isSafeInteger(entry.attempts) ? entry.attempts : 0) + 1;
      if (attempts > MAX_ATTEMPTS) {
        transaction.update(reportRef(reportId), {
          [`delivery.${channel}`]: {
            ...entry, status: "failed", updatedAt: Timestamp.fromMillis(nowMs),
          },
        });
        return null;
      }
      transaction.update(reportRef(reportId), {
        [`delivery.${channel}`]: {
          status: "sending",
          attempts,
          claimedAt: Timestamp.fromMillis(nowMs),
          lastErrorCode: typeof entry.lastErrorCode === "string" ? entry.lastErrorCode : null,
        },
      });
      return { report, attempts };
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

  async function sendGithub(reportId, report, config) {
    let includeDescription = false;
    if (config.includeDescription) {
      // Asked, not assumed: the repository's visibility is read at send time,
      // so a repository made public later never receives tester text.
      const repository = await githubRequest(`/repos/${config.githubRepo}`);
      if (!repository.ok) throw new DeliveryFailure(`http-${repository.status}`);
      const body = await repository.json().catch(() => ({}));
      includeDescription = body?.private === true;
    }
    const issue = buildBugReportIssue(reportId, report, { includeDescription });
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
      if (!claimed) {
        outcome[channel] = "skipped";
        continue;
      }
      try {
        const externalId = await SENDERS[channel](reportId, claimed.report, config[channel]);
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
  MAX_ATTEMPTS,
  buildBugReportEmail,
  buildBugReportIssue,
  createBugReportDelivery,
  escapeHtml,
  readConfig,
};
