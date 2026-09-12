// Reporting a third-party GIF, into the moderation queue that already exists.
//
// Two things make this different from every other report in the product, and
// both shape the record it writes:
//
//  1. NO YO VOICE ACCOUNT IS AT FAULT. A GIF is a third party's asset that our
//     own `g`-filtered proxy surfaced. `reportedUserId` is therefore `''` —
//     `ModerationReport.fromFirestore` already defaults that field to `''`, so
//     the Moderation Center renders it without a change — and nobody is
//     sanctioned for picking it out of a grid we showed them.
//  2. STAFF CANNOT READ `gifAssets`. So the evidence has to travel inside the
//     report: `targetTextSnapshot` carries `giphy:<id> — <title>` and
//     `targetMediaUrl` carries the pinned CDN URL, which is the only way a
//     moderator can actually look at the thing they are deciding about. This
//     mirrors the `reelComment` precedent exactly.
//
// Staff action reuses `moderateReport` — there is no new staff endpoint. A
// `contentRemoved` resolution on a `gifAsset` report sets `gifAssets.blocked`,
// which suppresses discovery and makes all transactional message publication
// refuse the asset. Discovery's hot-path index remains best-effort.

"use strict";

const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const {
  activeProfile,
  consumeRateLimit,
  digest,
  rateLimitReference,
  requireUid,
} = require("../../integrity/guards");
const { DAY_MS, REPORT_DAILY_LIMIT } = require("./rate_limit");
const { sanitizeTitle } = require("./normalize");

const {
  gifAssetDocumentId,
  gifCdnUrl,
  gifTargetId,
} = require("./gif_ref");

/// Same closed set as every other report surface in the product, so triage
/// filters keep working and a reporter cannot use the field as a message.
const GIF_REPORT_REASONS = Object.freeze([
  "spam",
  "harassment",
  "hate",
  "sexual",
  "violence",
  "selfHarm",
  "impersonation",
  "other",
]);
const GIF_REPORT_REASON_SET = new Set(GIF_REPORT_REASONS);

/// Reports needed before an asset is auto-suppressed from search.
///
/// Suppression is NOT blocking: it is reversible, it only affects discovery,
/// and it leaves the asset sendable and every already-sent bubble untouched.
/// The point is to stop a genuinely bad asset spreading during the hours
/// before a human reaches the queue, at a cost that a small brigade cannot
/// turn into a censorship tool for ordinary GIFs.
const AUTO_SUPPRESS_THRESHOLD = 3;

const MAX_REPORT_NOTE = 300;
const MAX_GIF_REPORT_EVIDENCE_LENGTH = 200;
const MAX_CONTEXT_PATH = 300;
const CONTEXT_PATH_PATTERN = /^[A-Za-z0-9/_-]{1,300}$/u;

function isValidReason(value) {
  return typeof value === "string" && GIF_REPORT_REASON_SET.has(value);
}

/// Where the reporter saw it. Optional, bounded, and grammar-checked because
/// it is displayed to staff — a moderator clicking a "context" value must not
/// be the way an attacker gets arbitrary text in front of them.
function normalizeContextPath(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_CONTEXT_PATH) return null;
  return CONTEXT_PATH_PATTERN.test(trimmed) ? trimmed : null;
}

/// The evidence line a moderator reads. Deliberately carries the provider and
/// id as well as the title: the title alone does not identify an asset, and
/// the id is what a block acts on.
function evidenceSnapshot({ provider, id, title }) {
  const prefix = `${provider}:${id} — `;
  const label = sanitizeTitle(title, { stripAttribution: false });
  return prefix + label.slice(0, Math.max(0, MAX_GIF_REPORT_EVIDENCE_LENGTH - prefix.length));
}

/// Deterministic report id: one reporter can file one report per asset.
///
/// A digest keeps all valid opaque UIDs and provider ids within the moderation
/// endpoint's safe 256-character grammar, without truncation or aliasing.
/// The existing-document check makes a retry one vote, never a second report.
function gifReportId(reporterId, provider, id) {
  return `gif_${digest("gif-report", reporterId, provider, id)}`;
}

function createGifModeration({ db, now = () => Date.now(), cache = null } = {}) {
  if (!db) throw new TypeError("A Firestore handle is required.");

  /// File one report and, if the asset has crossed the threshold, suppress it.
  ///
  /// Returns `{ reportId, created, suppressed }`. `created:false` is a
  /// successful, idempotent outcome — a person tapping Report twice has
  /// reported it, and telling them otherwise would be a lie that also teaches
  /// them the id scheme.
  async function reportAsset({
    reporterId,
    provider,
    gifId,
    reason,
    note = "",
    contextPath = null,
  }) {
    requireUid(reporterId, "reporterId");
    const documentId = gifAssetDocumentId(provider, gifId);
    const targetId = gifTargetId(provider, gifId);
    const url = gifCdnUrl(provider, gifId);
    if (documentId === null || targetId === null || url === null) {
      return { error: "invalid_target" };
    }
    if (!isValidReason(reason)) return { error: "invalid_reason" };

    const nowMs = now();
    const stamp = Timestamp.fromMillis(nowMs);
    const assetRef = db.collection("gifAssets").doc(documentId);
    const reportRef = db
      .collection("reports")
      .doc(gifReportId(reporterId, provider, gifId));
    const dailyScope = "gif.report.create";
    const dailyRef = rateLimitReference(db, dailyScope, reporterId);
    const reporterRef = db.doc(`users/${reporterId}`);

    const outcome = await db.runTransaction(async (transaction) => {
      const [assetSnapshot, existingReport, reporter, daily] = await Promise.all([
        transaction.get(assetRef),
        transaction.get(reportRef),
        transaction.get(reporterRef),
        transaction.get(dailyRef),
      ]);
      activeProfile(reporter, "Your");
      // An asset the proxy has never surfaced cannot be reported. This is not
      // pedantry: without it, `reports` becomes a way to write arbitrary ids
      // and titles into the moderation queue, and `gifAssets` becomes a way to
      // create documents the publishing transaction then trusts.
      if (!assetSnapshot.exists) return { error: "unknown_asset" };
      const asset = assetSnapshot.data() ?? {};

      if (existingReport.exists) {
        return {
          reportId: reportRef.id,
          created: false,
          suppressed: asset.blocked === true || asset.suppressed === true,
        };
      }

      consumeRateLimit(transaction, daily, {
        reference: dailyRef,
        scope: dailyScope,
        uid: reporterId,
        nowMs,
        now: stamp,
        maxEvents: REPORT_DAILY_LIMIT,
        windowMs: DAY_MS,
      });

      const priorCount = Number.isSafeInteger(asset.reportCount)
        ? asset.reportCount
        : 0;
      const nextCount = priorCount + 1;
      const shouldSuppress =
        nextCount >= AUTO_SUPPRESS_THRESHOLD && asset.blocked !== true;

      transaction.create(reportRef, {
        schemaVersion: 2,
        reporterId,
        targetType: "gifAsset",
        targetId,
        // Empty on purpose: no YO Voice account is responsible for a third
        // party's asset, and attaching one would put an innocent uid into a
        // sanction workflow.
        reportedUserId: "",
        contextPath: normalizeContextPath(contextPath),
        gifProvider: provider,
        gifId,
        targetTextSnapshot: evidenceSnapshot({
          provider,
          id: gifId,
          title: asset.title,
        }),
        // The only way a moderator can see the reported thing: staff cannot
        // read `gifAssets`, and the asset is not rehosted anywhere we control.
        targetMediaUrl: url,
        reason,
        note: typeof note === "string" ? note.slice(0, MAX_REPORT_NOTE) : "",
        status: "open",
        createdAt: stamp,
      });

      const assetUpdate = {
        reportCount: FieldValue.increment(1),
        lastReportedAt: stamp,
      };
      if (shouldSuppress) {
        assetUpdate.suppressed = true;
        assetUpdate.suppressedAt = stamp;
      }
      transaction.set(assetRef, assetUpdate, { merge: true });

      return { reportId: reportRef.id, created: true, suppressed: shouldSuppress };
    });

    if (outcome?.suppressed && cache) {
      // Outside the transaction on purpose: the suppression index is a cache,
      // and a failure to update it must not roll back a filed report.
      await cache.suppressAsset(documentId);
    }
    return outcome;
  }

  /// The durable block, called by `moderateReport` when staff resolve a
  /// `gifAsset` report with `contentRemoved`.
  ///
  /// Blocking suppresses discovery and prevents future sends. It does NOT
  /// retroactively blank bubbles already sent, because those hotlink the CDN
  /// and clients do not consult a blocklist at render time — the remedy for a
  /// specific message stays `adminDeleteMessage` / `moderateClubMessage`.
  async function blockAsset({ provider, gifId, blockedBy, transaction = null }) {
    const documentId = gifAssetDocumentId(provider, gifId);
    if (documentId === null) return { blocked: false, reason: "invalid_target" };
    const reference = db.collection("gifAssets").doc(documentId);
    const stamp = Timestamp.fromMillis(now());
    const apply = async (current) => {
      const snapshot = await current.get(reference);
      if (!snapshot.exists) return { blocked: false, reason: "unknown_asset" };
      const asset = snapshot.data() ?? {};
      if (asset.provider !== provider || asset.gifId !== gifId) {
        return { blocked: false, reason: "invalid_record" };
      }
      const alreadyBlocked = asset.blocked === true;
      if (!alreadyBlocked) {
        current.set(reference, {
          blocked: true,
          blockedAt: stamp,
          blockedBy: typeof blockedBy === "string" ? blockedBy : null,
          suppressed: true,
        }, { merge: true });
      }
      return { blocked: !alreadyBlocked, reason: null };
    };
    const outcome = transaction ? await apply(transaction) : await db.runTransaction(apply);
    // With a caller-owned transaction the caller refreshes this cache only
    // after its own commit. Durable blocking never depends on that refresh.
    if (!transaction && outcome.reason === null && cache) {
      await cache.suppressAsset(documentId);
    }
    return outcome;
  }

  return {
    AUTO_SUPPRESS_THRESHOLD,
    blockAsset,
    reportAsset,
  };
}

module.exports = {
  AUTO_SUPPRESS_THRESHOLD,
  GIF_REPORT_REASONS,
  MAX_REPORT_NOTE,
  MAX_GIF_REPORT_EVIDENCE_LENGTH,
  createGifModeration,
  evidenceSnapshot,
  gifReportId,
  isValidReason,
  normalizeContextPath,
};
