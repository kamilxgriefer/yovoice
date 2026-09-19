// Retention artefacts for account deletion.
//
// ADR-206's rule: delete or irreversibly anonymize every personal-data
// location, and retain only what a NAMED legal or abuse reason requires. This
// module owns the two retentions that need code rather than a policy sentence:
//
//   1. `deletedAccountDigests/{digest}` — a salted SHA-256 of the lowercased
//      e-mail, written ONLY when the account was `banned == true` at deletion.
//      Without it, deleting an account is a one-click ban reset. A non-banned
//      account leaves nothing behind here.
//   2. Reports FILED BY the deleted user — retained as third-party abuse
//      evidence, but re-keyed, because the report document id embeds the
//      reporter's raw uid (`{uid}_{targetType}_{targetId}`, firestore.rules)
//      and anonymizing only the field would leave the uid in the path.
//
// The salt is deliberately NOT a `defineSecret` parameter: Firebase collects
// every eagerly declared SecretParam during deploy discovery, so declaring one
// here would make the whole catalog undeployable until the secret exists (the
// GIPHY lesson, functions/media/gif/catalog.js). It is read from the process
// environment, and when it is absent the digest is SKIPPED rather than written
// unsalted — a reversible "hash" of an e-mail address is worse than no row at
// all. The skip is recorded on the outbox row so it is visible, not silent.
//
// The reporter tombstone is NOT a hash. It is random, minted once per deletion
// and carried on the outbox row, so a retry re-keys to the same id and nobody
// — including us — can link a retained report back to the account. The dedupe
// invariant the raw-uid id provided is lost, which is acceptable precisely
// because a deleted account can never file another report.

const crypto = require("node:crypto");

const DELETED_REPORTER_PREFIX = "deleted:";
const DELETED_REPORT_ID_PREFIX = "deleted-";
const DIGEST_SALT_ENV = "YOVOICE_DELETED_ACCOUNT_DIGEST_SALT";
const MIN_SALT_LENGTH = 16;
const TOMBSTONE_HEX_LENGTH = 32;
// A Firestore document id is capped at 1500 bytes. Reports are keyed
// `{reporter}_{targetType}_{targetId}`; targetId is capped at 128 by the
// create rule and targetType is a short enum, so a 32-hex tombstone plus the
// prefix stays far inside the limit.
const MAX_REPORT_ID_LENGTH = 1500;

/**
 * The salt, or null when the operator has not configured one.
 *
 * Never logged, never returned to a caller, never written to Firestore.
 */
function digestSalt(env = process.env) {
  const value = typeof env?.[DIGEST_SALT_ENV] === "string"
    ? env[DIGEST_SALT_ENV].trim()
    : "";
  return value.length >= MIN_SALT_LENGTH ? value : null;
}

/**
 * A salted, lowercased-e-mail digest for honouring a ban past deletion.
 *
 * Returns null — never a weaker value — when there is no salt or no e-mail.
 */
function deletedAccountEmailDigest(email, { salt = digestSalt() } = {}) {
  if (typeof salt !== "string" || salt.length < MIN_SALT_LENGTH) return null;
  const normalized = typeof email === "string" ? email.trim().toLowerCase() : "";
  if (!normalized || normalized.length > 320 || !normalized.includes("@")) {
    return null;
  }
  return crypto
    .createHmac("sha256", salt)
    .update(`deleted-account-email\0${normalized}`)
    .digest("hex");
}

/** A fresh, unlinkable reporter tombstone. Minted once, reused by retries. */
function mintReporterTombstone(randomBytes = crypto.randomBytes) {
  return randomBytes(TOMBSTONE_HEX_LENGTH / 2).toString("hex");
}

function isReporterTombstone(value) {
  return typeof value === "string" &&
    new RegExp(`^[0-9a-f]{${TOMBSTONE_HEX_LENGTH}}$`, "u").test(value);
}

/**
 * The value that replaces `reporterId` on a retained report.
 *
 * `isValidOpaqueUid` (functions/achievements/identity.js) accepts it — it is a
 * bounded string with no slash and no control characters — so `moderateReport`
 * and `listReportAuditTrail` keep working on a re-keyed row. A Firebase uid is
 * alphanumeric and can never contain ':', so the prefix cannot collide with a
 * live account.
 */
function deletedReporterId(tombstone) {
  if (!isReporterTombstone(tombstone)) {
    throw new TypeError("A canonical reporter tombstone is required.");
  }
  return `${DELETED_REPORTER_PREFIX}${tombstone}`;
}

function isDeletedReporterId(value) {
  return typeof value === "string" && value.startsWith(DELETED_REPORTER_PREFIX);
}

/**
 * The re-keyed report document id.
 *
 * The suffix after the reporter segment is preserved exactly, so the
 * `{reporter}_{targetType}_{targetId}` convention survives the move and a
 * moderator reading the id still sees what was reported.
 */
function deletedReportId(reportId, uid, tombstone) {
  if (typeof reportId !== "string" || typeof uid !== "string" || !uid) {
    return null;
  }
  const marker = `${uid}_`;
  if (!reportId.startsWith(marker)) return null;
  const suffix = reportId.slice(marker.length);
  if (!suffix) return null;
  const rekeyed =
    `${DELETED_REPORT_ID_PREFIX}${tombstone}_${suffix}`;
  if (
    rekeyed.length > MAX_REPORT_ID_LENGTH ||
    rekeyed.includes("/") ||
    /[\0-\x1f\x7f]/u.test(rekeyed)
  ) {
    return null;
  }
  return rekeyed;
}

module.exports = {
  DELETED_REPORTER_PREFIX,
  DELETED_REPORT_ID_PREFIX,
  DIGEST_SALT_ENV,
  MIN_SALT_LENGTH,
  deletedAccountEmailDigest,
  deletedReportId,
  deletedReporterId,
  digestSalt,
  isDeletedReporterId,
  isReporterTombstone,
  mintReporterTombstone,
};
