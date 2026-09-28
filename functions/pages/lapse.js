// The Page lapse state machine (ADR-233 §2.8, owner decision O3). Pure.
//
//   stored            condition                          effective
//   active            capability                         active
//   active/readOnly   capability lost                    readOnly
//   readOnly          now - lapsedAt >= 30 d             hidden
//   hidden            (no capability)                    hidden
//   any               capability restored                active
//
// With lapseEnabled false (appConfig/pagesV1, the emergency brake) nothing is
// DOWNGRADED at read time: the stored status is the effective one. Restores
// still run: a live capability is always "active".
//
// Transitions that WRITE (the sweep, the capability triggers) belong to the
// lapse package; every writer re-derives the capability inside its own
// transaction, so a stale reader can never overwrite a restore.

const { timestampMillis } = require("../integrity/guards");

const PAGE_READ_ONLY_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;

function effectivePageStatus(page, capabilityAllowed, nowMs, lapseEnabled) {
  if (!page) return null;
  if (capabilityAllowed === true) return "active";
  if (lapseEnabled !== true) return page.status;
  if (page.status === "active") return "readOnly";
  if (page.status === "readOnly") {
    const lapsedAtMs = timestampMillis(page.lapsedAt);
    if (lapsedAtMs !== null && Number.isSafeInteger(nowMs) &&
        nowMs - lapsedAtMs >= PAGE_READ_ONLY_WINDOW_MS) {
      return "hidden";
    }
    return "readOnly";
  }
  return "hidden";
}

/// The status a READ applies when it does not re-derive the capability
/// (feed, wall, Find): the stored status with the 30-day boundary (§2.8
/// source 4). A stored `active` Page stays active here even if its grant has
/// expired; the sweep, the capability triggers and every write path move it.
/// With lapseEnabled false the stored status is returned unchanged.
function readTimePageStatus(page, nowMs, lapseEnabled) {
  if (!page) return null;
  if (page.status !== "readOnly" || lapseEnabled !== true) return page.status;
  const lapsedAtMs = timestampMillis(page.lapsedAt);
  if (lapsedAtMs !== null && Number.isSafeInteger(nowMs) &&
      nowMs - lapsedAtMs >= PAGE_READ_ONLY_WINDOW_MS) {
    return "hidden";
  }
  return "readOnly";
}

/// The field changes that restore a lapsed Page to `active` (capability is
/// back). Empty when the Page is already active. `listed` is recomputed by
/// the caller from the merged document.
function restoredPageFields(page) {
  if (!page || page.status === "active") return {};
  return { status: "active", lapsedAt: null };
}

module.exports = {
  PAGE_READ_ONLY_WINDOW_MS,
  effectivePageStatus,
  readTimePageStatus,
  restoredPageFields,
};
