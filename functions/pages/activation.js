// Runtime activation switch for Premium Pages (ADR-233 §2.1).
//
// `appConfig/pagesV1` is server-only (firestore.rules denies every client read
// and write under appConfig/*) and written by an operator with Admin
// credentials (scripts/set_pages_activation.js), never by a callable. It is
// read UNCACHED on every non-safety call, so the kill switch takes effect on
// the next invocation. Exact shape:
//
//   { schemaVersion: 1,
//     readAccess:  "disabled" | "testers" | "all",
//     writeAccess: "disabled" | "testers" | "all",
//     testerUids:  [<= 100 distinct uids],
//     lapseEnabled: bool,
//     revision: int >= 1 }
//
// FAIL CLOSED: a missing, unreadable or malformed document (a missing or
// extra key, a wrong type, a duplicate or malformed tester uid, tester uids
// outside "testers" mode, or a writeAccess WIDER than readAccess, which would
// let somebody publish what nobody can read) means everything disabled and
// lapseEnabled false.
//
// SAFETY ACTIONS NEVER READ THIS DOCUMENT (PAGES_SAFETY_ACTIONS below). The
// kill switch hides Pages; it must never stop an owner from pausing a Page,
// deleting a post or a comment, a viewer from reporting or unfollowing, or
// anybody from making their profile private.

const { HttpsError } = require("firebase-functions/v2/https");
const defaultLogger = require("firebase-functions/logger");

const { isValidOpaqueUid } = require("../integrity/guards");

const PAGES_ACTIVATION_PATH = "appConfig/pagesV1";
const PAGES_ACTIVATION_KEYS = Object.freeze([
  "lapseEnabled",
  "readAccess",
  "revision",
  "schemaVersion",
  "testerUids",
  "writeAccess",
]);
const PAGES_ACCESS_MODES = Object.freeze(["disabled", "testers", "all"]);
const PAGES_MAX_TESTERS = 100;
const PAGES_NOT_ENABLED_MESSAGE = "Pages are not available yet.";
const PAGES_NOT_ENABLED_REASON = "pagesNotEnabled";

// Documentation and test anchor: the operations that must work with
// readAccess "disabled". Each one is implemented without a call into this
// module (pages_activation.test.js proves it per package).
const PAGES_SAFETY_ACTIONS = Object.freeze([
  "managePageV1.pause",
  "managePagePostV1.delete",
  "pagePostEngagementV1.deleteComment",
  "createPageReportV1",
  "setFollow.unfollow",
  "setMyProfileVisibility",
  // ADR-236 (pages/deletion.js): asking for a Page's deletion, TAKING IT
  // BACK (the cancel; the resume that may follow it is gated), "delete now"
  // and "delete all posts". pages_page_deletion.test.js proves each one.
  "managePageDeletionV1.request",
  "managePageDeletionV1.restore",
  "managePageDeletionV1.purgeNow",
  "managePageDeletionV1.clearPosts",
]);

const DISABLED = Object.freeze({
  schemaVersion: 1,
  readAccess: "disabled",
  writeAccess: "disabled",
  testerUids: Object.freeze([]),
  lapseEnabled: false,
  revision: 0,
});

function accessRank(mode) {
  return PAGES_ACCESS_MODES.indexOf(mode);
}

function malformedReason(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) return "notAnObject";
  const keys = Object.keys(data).sort();
  if (keys.length !== PAGES_ACTIVATION_KEYS.length ||
      keys.some((key, index) => key !== PAGES_ACTIVATION_KEYS[index])) {
    return "keys";
  }
  if (data.schemaVersion !== 1) return "schemaVersion";
  if (!PAGES_ACCESS_MODES.includes(data.readAccess)) return "readAccess";
  if (!PAGES_ACCESS_MODES.includes(data.writeAccess)) return "writeAccess";
  if (accessRank(data.writeAccess) > accessRank(data.readAccess)) {
    return "writeWiderThanRead";
  }
  if (typeof data.lapseEnabled !== "boolean") return "lapseEnabled";
  if (!Number.isSafeInteger(data.revision) || data.revision < 1) return "revision";
  if (!Array.isArray(data.testerUids) || data.testerUids.length > PAGES_MAX_TESTERS) {
    return "testerUids";
  }
  const seen = new Set();
  for (const uid of data.testerUids) {
    if (!isValidOpaqueUid(uid) || seen.has(uid)) return "testerUids";
    seen.add(uid);
  }
  const usesTesters = data.readAccess === "testers" || data.writeAccess === "testers";
  if (!usesTesters && data.testerUids.length !== 0) return "testerUidsUnused";
  return null;
}

/// The canonical activation for a snapshot. Never throws: anything but the
/// exact shape is DISABLED.
function canonicalPagesActivation(snapshot) {
  if (!snapshot?.exists) return DISABLED;
  const data = snapshot.data();
  if (malformedReason(data) !== null) return DISABLED;
  return Object.freeze({
    schemaVersion: 1,
    readAccess: data.readAccess,
    writeAccess: data.writeAccess,
    testerUids: Object.freeze([...data.testerUids]),
    lapseEnabled: data.lapseEnabled,
    revision: data.revision,
  });
}

function modeAllows(mode, activation, uid) {
  if (mode === "all") return true;
  if (mode === "testers") {
    return typeof uid === "string" && activation.testerUids.includes(uid);
  }
  return false;
}

function pagesReadAllowed(activation, uid) {
  return modeAllows(activation?.readAccess, activation, uid);
}

// Write implies read: the canonical form already forbids write wider than
// read, and this checks both so a hand-built object cannot bypass it.
function pagesWriteAllowed(activation, uid) {
  return pagesReadAllowed(activation, uid) &&
    modeAllows(activation?.writeAccess, activation, uid);
}

function pagesNotEnabledError() {
  return new HttpsError(
    "failed-precondition",
    PAGES_NOT_ENABLED_MESSAGE,
    { reason: PAGES_NOT_ENABLED_REASON },
  );
}

/// One uncached plain read. An unreadable document is DISABLED (logged
/// without any uid), never an `unavailable` a client might retry into.
async function readPagesActivation({ db, logger = defaultLogger }) {
  if (typeof db?.doc !== "function") {
    throw new TypeError("A Firestore handle is required for Pages activation.");
  }
  let snapshot;
  try {
    snapshot = await db.doc(PAGES_ACTIVATION_PATH).get();
  } catch (error) {
    logger.error("pages activation unreadable", {
      code: typeof error?.code === "string" || Number.isSafeInteger(error?.code)
        ? error.code
        : null,
    });
    return DISABLED;
  }
  if (snapshot.exists && malformedReason(snapshot.data()) !== null) {
    logger.error("pages activation malformed", {
      reason: malformedReason(snapshot.data()),
    });
  }
  return canonicalPagesActivation(snapshot);
}

async function assertPagesReadEnabled({ db, uid, logger = defaultLogger }) {
  const activation = await readPagesActivation({ db, logger });
  if (!pagesReadAllowed(activation, uid)) throw pagesNotEnabledError();
  return activation;
}

async function assertPagesWriteEnabled({ db, uid, logger = defaultLogger }) {
  const activation = await readPagesActivation({ db, logger });
  if (!pagesWriteAllowed(activation, uid)) throw pagesNotEnabledError();
  return activation;
}

module.exports = {
  PAGES_ACCESS_MODES,
  PAGES_ACTIVATION_KEYS,
  PAGES_ACTIVATION_PATH,
  PAGES_DISABLED_ACTIVATION: DISABLED,
  PAGES_MAX_TESTERS,
  PAGES_NOT_ENABLED_MESSAGE,
  PAGES_NOT_ENABLED_REASON,
  PAGES_SAFETY_ACTIONS,
  assertPagesReadEnabled,
  assertPagesWriteEnabled,
  canonicalPagesActivation,
  malformedPagesActivationReason: malformedReason,
  pagesNotEnabledError,
  pagesReadAllowed,
  pagesWriteAllowed,
  readPagesActivation,
};
