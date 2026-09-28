// Runtime activation switch for "See who liked" (ADR-230).
//
// `appConfig/likersV1` is server-only (firestore.rules denies every client
// read and write under appConfig/*) and written by an operator with Admin
// credentials only, never by a callable. It is read once per list call,
// AFTER exact input and BEFORE any rate budget, gate or content read, so a
// disabled feature costs the caller nothing and the answer depends on nothing
// about other users.
//
// Exact shape (owner answer 2026-09-28: every pre-launch like is listable, so
// there is no `listedSince` bound):
//
//   { schemaVersion: 1, enabled: bool, serverMessagesEnabled: bool,
//     updatedAt: Timestamp }
//
// A missing document, a missing or extra key (including a stale
// `listedSince`), or a wrong type means DISABLED. Fail closed.

const { HttpsError } = require("firebase-functions/v2/https");

const { timestampMillis } = require("../integrity/guards");

const LIKERS_ACTIVATION_PATH = "appConfig/likersV1";
const LIKERS_ACTIVATION_KEYS = Object.freeze([
  "enabled",
  "schemaVersion",
  "serverMessagesEnabled",
  "updatedAt",
]);
const LIKERS_SURFACES = Object.freeze({
  CONTENT: "content",
  SERVER_MESSAGE: "serverMessage",
});
const LIKERS_NOT_ENABLED_MESSAGE = "See who liked is not available yet.";
const LIKERS_NOT_ENABLED_REASON = "likersNotEnabled";

const DISABLED = Object.freeze({ enabled: false, serverMessagesEnabled: false });

function canonicalLikersActivation(snapshot) {
  if (!snapshot?.exists) return DISABLED;
  const data = snapshot.data();
  if (!data || typeof data !== "object" || Array.isArray(data)) return DISABLED;
  const keys = Object.keys(data).sort();
  if (
    keys.length !== LIKERS_ACTIVATION_KEYS.length ||
    keys.some((key, index) => key !== LIKERS_ACTIVATION_KEYS[index]) ||
    data.schemaVersion !== 1 ||
    typeof data.enabled !== "boolean" ||
    typeof data.serverMessagesEnabled !== "boolean" ||
    timestampMillis(data.updatedAt) === null
  ) {
    return DISABLED;
  }
  return Object.freeze({
    enabled: data.enabled,
    serverMessagesEnabled: data.serverMessagesEnabled,
  });
}

function likersSurfaceEnabled(activation, surface) {
  if (surface === LIKERS_SURFACES.CONTENT) return activation?.enabled === true;
  if (surface === LIKERS_SURFACES.SERVER_MESSAGE) {
    return activation?.enabled === true &&
      activation?.serverMessagesEnabled === true;
  }
  throw new TypeError(`Unknown likers surface: ${surface}`);
}

function likersNotEnabledError() {
  return new HttpsError(
    "failed-precondition",
    LIKERS_NOT_ENABLED_MESSAGE,
    { reason: LIKERS_NOT_ENABLED_REASON },
  );
}

// One plain read (no transaction). Throws the documented refusal when the
// surface is off; returns the canonical activation otherwise.
async function assertLikersEnabled({ db, surface }) {
  if (!Object.values(LIKERS_SURFACES).includes(surface)) {
    throw new TypeError(`Unknown likers surface: ${surface}`);
  }
  const activation = canonicalLikersActivation(
    await db.doc(LIKERS_ACTIVATION_PATH).get(),
  );
  if (!likersSurfaceEnabled(activation, surface)) throw likersNotEnabledError();
  return activation;
}

module.exports = {
  LIKERS_ACTIVATION_KEYS,
  LIKERS_ACTIVATION_PATH,
  LIKERS_NOT_ENABLED_MESSAGE,
  LIKERS_NOT_ENABLED_REASON,
  LIKERS_SURFACES,
  assertLikersEnabled,
  canonicalLikersActivation,
  likersNotEnabledError,
  likersSurfaceEnabled,
};
