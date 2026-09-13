"use strict";

/**
 * The OLD-CLIENT GATE.
 *
 * The installed Flutter client lists a Club's channels with a bare
 * `orderBy('position')` and no equality filters
 * (`lib/features/clubs/data/services/club_service.dart` `watchChannels`). The
 * V1 `list` rule for `clubs/{id}/channels` requires the query itself to pin
 * `accessMode == 'members' && status == 'active'` (`firestore.rules`, the
 * `allow list` branch under `match /channels/{channelId}`). Firestore Rules
 * are evaluated against the QUERY'S CONSTRAINTS, never against the documents
 * that come back, so an unpinned query over a versioned root is denied
 * WHOLESALE — it is not filtered down to the readable rows.
 *
 * Two corrections to the folklore, both verified on the emulator by
 * `firestore-tests/server_rules.test.js`:
 *
 *  1. The denial does NOT wait for the first restricted channel. It starts the
 *     instant the ROOT carries a server marker, because `isLegacyClub()` reads
 *     the root, not the channel. A migrated root whose every channel is
 *     `accessMode: "members"` already denies the old query.
 *  2. The failure is loud and closed (`permission-denied`), not a short list.
 *     The old client renders it as an empty channel list because its
 *     StreamBuilder has no error branch — silent to the user, which is exactly
 *     why the gate has to be enforced before the write, not detected after it.
 *
 * Rules cannot fix this: there is no rule that makes an unpinned query legal
 * without also making every restricted document readable. The only correct
 * enforcement is therefore to refuse to version a root until the incompatible
 * client cohort is gone. This module is that gate's data contract and its
 * pure evaluator; `migration_apply.js` is the enforcement point.
 *
 * `serverMigrationGates/{CLIENT_GATE_ID}` is server-written and client
 * readable so a compatible client can render an honest "update required"
 * state instead of an empty screen. It carries no personal data.
 */

const { fail, isValidOpaqueUid, timestampMillis } = require("../integrity/guards");

const CLIENT_GATE_VERSION = 1;
const CLIENT_GATE_ID = "clientCompatibilityV1";
const CLIENT_GATE_COLLECTION = "serverMigrationGates";
const CLIENT_GATE_PATH = `${CLIENT_GATE_COLLECTION}/${CLIENT_GATE_ID}`;
const GATE_STATUSES = Object.freeze(["open", "satisfied"]);
// Every platform the Flutter app is built for. A census entry naming an
// unknown platform is not silently ignored; it is counted as incompatible.
const CLIENT_PLATFORMS = Object.freeze(["android", "ios", "web", "macos", "windows", "linux"]);
const MIN_BUILD = 1;
const MAX_BUILD = 1_000_000_000;
const MAX_CENSUS_ENTRIES = 64;
const MAX_CENSUS_SESSIONS = 1_000_000_000;
const SEMVER = /^(?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]{0,3})$/u;

function gateFailure(message) {
  fail("failed-precondition", message);
}

// Every malformed field in the gate is a failed PRECONDITION on the run, not
// a caller argument error: the gate is server data, so its shape is never the
// operator's input mistake. Keeping one code makes the refusal set closed.
function positive(value, max) {
  if (!Number.isSafeInteger(value) || value < MIN_BUILD || value > max) {
    gateFailure("The client compatibility gate needs reconciliation.");
  }
  return value;
}

/**
 * The published gate document, validated field by field. Anything unexpected
 * — a missing field, an unknown status, a non-integer build, a platform this
 * build of the app does not have — fails closed. A gate that cannot be read
 * canonically is an OPEN gate, never an absent constraint.
 */
function canonicalClientGate(snapshot) {
  const gate = snapshot?.exists ? snapshot.data() : null;
  if (!gate) gateFailure("The client compatibility gate has not been published.");
  if (gate.schemaVersion !== CLIENT_GATE_VERSION || gate.gateId !== CLIENT_GATE_ID) {
    gateFailure("The client compatibility gate needs reconciliation.");
  }
  if (typeof gate.minimumClientVersion !== "string" || !SEMVER.test(gate.minimumClientVersion)) {
    gateFailure("The client compatibility gate carries no usable minimum version.");
  }
  const minimumClientBuild = positive(gate.minimumClientBuild, MAX_BUILD);
  const platforms = gate.platformMinimumBuild;
  if (platforms === null || typeof platforms !== "object" || Array.isArray(platforms) ||
      Object.keys(platforms).length !== CLIENT_PLATFORMS.length ||
      CLIENT_PLATFORMS.some((platform) => !Object.hasOwn(platforms, platform))) {
    gateFailure("The client compatibility gate needs a build floor for every platform.");
  }
  const platformMinimumBuild = {};
  for (const platform of CLIENT_PLATFORMS) {
    const build = positive(platforms[platform], MAX_BUILD);
    // A per-platform floor may be stricter than the global one, never laxer:
    // otherwise one lenient platform quietly reopens the gate for everyone.
    if (build < minimumClientBuild) gateFailure("A platform build floor is below the gate minimum.");
    platformMinimumBuild[platform] = build;
  }
  if (!GATE_STATUSES.includes(gate.status)) gateFailure("The client compatibility gate status is unsupported.");
  const revision = positive(gate.revision, Number.MAX_SAFE_INTEGER - 1);
  const attestedBy = gate.attestedBy ?? null;
  const attestedAtMs = gate.attestedAt === null || gate.attestedAt === undefined
    ? null : timestampMillis(gate.attestedAt);
  if (gate.status === "satisfied" && (!isValidOpaqueUid(attestedBy) || attestedAtMs === null)) {
    // "Satisfied" is a human attestation about the installed base, not a fact
    // any server can derive. An unattributed one is not accepted.
    gateFailure("A satisfied client compatibility gate must name who attested it and when.");
  }
  if (gate.status === "open" && (attestedBy !== null || attestedAtMs !== null)) {
    gateFailure("An open client compatibility gate must carry no attestation.");
  }
  return Object.freeze({
    schemaVersion: CLIENT_GATE_VERSION, gateId: CLIENT_GATE_ID,
    minimumClientVersion: gate.minimumClientVersion, minimumClientBuild,
    platformMinimumBuild: Object.freeze(platformMinimumBuild),
    status: gate.status, revision, attestedBy: gate.status === "satisfied" ? attestedBy : null,
    attestedAtMs,
  });
}

/**
 * One installed-client observation against the gate. `build` is the platform
 * build number (`PackageInfo.buildNumber`), which is monotonic per platform
 * and is the only field that can be compared safely; the semantic version is
 * carried for humans. An unknown platform, a malformed build or a build below
 * the platform floor is incompatible. There is no benefit of the doubt.
 */
function clientMeetsGate(gate, claim) {
  if (claim === null || typeof claim !== "object" || Array.isArray(claim)) return false;
  const platform = claim.platform;
  if (typeof platform !== "string" || !CLIENT_PLATFORMS.includes(platform)) return false;
  const build = claim.build;
  if (!Number.isSafeInteger(build) || build < MIN_BUILD || build > MAX_BUILD) return false;
  return build >= gate.platformMinimumBuild[platform];
}

/**
 * The operator's observed installed-base census, the evidence half of the
 * gate. It is deliberately supplied, not derived: nothing in this repository
 * observes live client versions, and inventing a zero would be exactly the
 * fabricated-evidence failure this project has a written rule against.
 *
 * Returns the number of sessions that would lose their channel list, plus the
 * platforms they are on. `null` means the operator supplied no census at all,
 * which is treated as "unknown", never as "none".
 *
 * AN EMPTY CENSUS IS THE SAME UNKNOWN. `[]`, and a census whose every row
 * reports `sessions: 0`, are zero OBSERVATIONS — not an observation of zero.
 * Both used to satisfy the gate outright, which made the one control standing
 * between a migration and every installed client losing its channel list
 * pass by the absence of evidence. An analytics export that returned no rows,
 * or a hand-written placeholder, is exactly how that reaches an operator. The
 * unsupplied answer is returned instead, so the existing
 * `client-compatibility-census-not-supplied` refusal fires, and the coverage
 * requirement below is stated positively: every platform the gate names must
 * appear with a real session count, because a census that never mentions iOS
 * says nothing whatsoever about iOS.
 */
function evaluateClientCensus(gate, census) {
  if (census === null || census === undefined) {
    return { supplied: false, incompatibleSessions: null, compatibleSessions: null, platforms: [] };
  }
  if (!Array.isArray(census) || census.length > MAX_CENSUS_ENTRIES) {
    gateFailure("The client compatibility census is invalid.");
  }
  let incompatibleSessions = 0;
  let compatibleSessions = 0;
  const platforms = new Set();
  const observedPlatforms = new Set();
  for (const entry of census) {
    if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
      gateFailure("The client compatibility census is invalid.");
    }
    const sessions = entry.sessions;
    if (!Number.isSafeInteger(sessions) || sessions < 0 || sessions > MAX_CENSUS_SESSIONS) {
      gateFailure("The client compatibility census is invalid.");
    }
    if (sessions > 0 && typeof entry.platform === "string" && CLIENT_PLATFORMS.includes(entry.platform)) {
      observedPlatforms.add(entry.platform);
    }
    if (clientMeetsGate(gate, entry)) {
      compatibleSessions += sessions;
    } else {
      incompatibleSessions += sessions;
      if (sessions > 0 && typeof entry.platform === "string" && CLIENT_PLATFORMS.includes(entry.platform)) {
        platforms.add(entry.platform);
      }
    }
  }
  // Zero observations, and partial coverage, are both "unknown". A census
  // that reports nothing at all, or nothing for a platform the gate pins a
  // build floor on, cannot be read as that platform having no installed base.
  const covered = CLIENT_PLATFORMS.every((platform) => observedPlatforms.has(platform));
  if (incompatibleSessions + compatibleSessions === 0 || !covered) {
    return {
      supplied: false, incompatibleSessions: null, compatibleSessions: null,
      platforms: [], observedPlatforms: [...observedPlatforms].sort(),
    };
  }
  return {
    supplied: true, incompatibleSessions, compatibleSessions,
    platforms: [...platforms].sort(), observedPlatforms: [...observedPlatforms].sort(),
  };
}

/**
 * The one question the apply engine asks. Every clause is a refusal reason
 * from a closed set; none of them quotes an id, a name or a URL.
 */
function assessClientGate({ snapshot, expectedRevision, census }) {
  const gate = canonicalClientGate(snapshot);
  const reasons = [];
  if (gate.status !== "satisfied") reasons.push("client-compatibility-gate-not-satisfied");
  if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 1) {
    // The reviewed revision is part of the authorization for the irreversible
    // root flip, not an optional operator hint. Missing and malformed pins are
    // therefore an explicit closed-gate result rather than a wildcard.
    reasons.push("client-compatibility-gate-revision-required");
  } else if (gate.revision !== expectedRevision) {
    // The operator pins the revision they reviewed. A gate edited between
    // review and apply is a different decision and stops the run.
    reasons.push("client-compatibility-gate-revision-mismatch");
  }
  const observed = evaluateClientCensus(gate, census);
  if (!observed.supplied) reasons.push("client-compatibility-census-not-supplied");
  else if (observed.incompatibleSessions > 0) reasons.push("incompatible-client-cohort-observed");
  return { gate, observed, reasons: [...new Set(reasons)].sort(), satisfied: reasons.length === 0 };
}

module.exports = {
  CLIENT_GATE_COLLECTION, CLIENT_GATE_ID, CLIENT_GATE_PATH, CLIENT_GATE_VERSION,
  CLIENT_PLATFORMS, GATE_STATUSES, MAX_BUILD, MAX_CENSUS_ENTRIES, MIN_BUILD,
  assessClientGate, canonicalClientGate, clientMeetsGate, evaluateClientCensus,
};
