// The shared body of the three "See who liked" list callables (ADR-230):
// listVoiceMomentLikersV1, listReelLikersV1 and
// listServerChannelMessageReactorsV1.
//
// The three are family-local exports (each authorizes its target with its own
// family's audience machinery), but the order and the error envelope are one
// contract, so they live here once:
//
//   1. auth          requireActor (unverified email allowed, as the views)
//   2. exact input   requireLikersListInput: fixed page size, no `limit`
//   3. activation    appConfig/likersV1                } admitLikersList,
//   4. budgets       likers.list / listHourly / Daily  } OUTSIDE the uniform
//   5. gate          paid / canonical VIP / staff      } refusal
//   6. content       the family's `openTarget`, the liker scan, the family's
//                    fresh parent re-check and the cursor create(), INSIDE
//                    the uniform refusal
//
// Steps 3-5 describe only the caller (or nobody), so their codes and reasons
// reach the client unchanged. Every content-side refusal (parent missing,
// expired, deleted or malformed; parent or comment author hidden from the
// caller; channel ACL; message gone) collapses to ONE permission-denied, so
// the callable is no oracle for somebody else's state. invalid-argument (a
// stale, foreign or expired cursor) and resource-exhausted still propagate:
// they describe the caller's own request.
//
// No read-write transaction runs here except the rate-limit one inside
// admitLikersList, whose read set is the three privateRateLimits documents.
// The target, the candidates and every liker context are plain reads.

const { fail, requireActor } = require("../integrity/guards");
const { likerResolver } = require("./liker_audience");
const { likersTargetKey } = require("./liker_cursors");
const { admitLikersList } = require("./likers_admission");
const { runLikersPage, requireLikersListInput } = require("./likers_paging");

const LIKERS_UNAVAILABLE_MESSAGE = "This content is unavailable.";
const LIKERS_UNIFORM_REFUSAL_CODES = Object.freeze([
  "not-found",
  "failed-precondition",
  "permission-denied",
  "data-loss",
]);

// A plain (non-transactional) batch read with the same call shape as
// transaction.getAll, so the family audience helpers written against a
// transaction can run without taking a single lock.
function plainGetAll(db) {
  return async (...references) => {
    if (references.length === 0) return [];
    if (typeof db.getAll === "function") return db.getAll(...references);
    return Promise.all(references.map((reference) => reference.get()));
  };
}

// A read-only stand-in for a transaction: get / getAll only. Passing it where
// a helper expects a transaction makes every write attempt a TypeError
// instead of a silent lock.
function plainReader(db) {
  const getAll = plainGetAll(db);
  return Object.freeze({
    get: (referenceOrQuery) => referenceOrQuery.get(),
    getAll,
  });
}

function collapseContentRefusal(error) {
  if (LIKERS_UNIFORM_REFUSAL_CODES.includes(error?.code)) {
    fail("permission-denied", LIKERS_UNAVAILABLE_MESSAGE);
  }
  throw error;
}

/**
 * Serves one likers page.
 *
 * `openTarget({input, auth, admitted, timing, reader, getAll})` authorizes the
 * target for the caller with the family's own rules and returns
 * `{fetchCandidates, recheck, likerSurface?, serverId?, server?}`:
 *   - fetchCandidates(afterPosition, want): the likers_paging fetcher;
 *   - recheck(): the fresh response-time parent check (throws to refuse);
 *   - likerSurface: "content" (default) or "serverMessage" (adds the member
 *     row to the liker predicate; needs serverId and the canonical server).
 */
async function serveLikersList({
  db,
  Timestamp,
  request,
  family,
  surface,
  time,
  logger = undefined,
  randomBytes = undefined,
  openTarget,
}) {
  if (!db?.doc || !Timestamp?.fromMillis || typeof time !== "function" ||
      typeof openTarget !== "function") {
    throw new TypeError("db, Timestamp, time and openTarget are required.");
  }
  const auth = requireActor(request, { verified: false });
  const input = requireLikersListInput(family, request.data);
  const timing = time();
  const admitted = await admitLikersList({
    db,
    auth,
    surface,
    timing,
    ...(logger ? { logger } : {}),
  });
  const getAll = plainGetAll(db);
  try {
    const target = await openTarget({
      input,
      auth,
      admitted,
      timing,
      reader: plainReader(db),
      getAll,
    });
    const likerSurface = target?.likerSurface ?? "content";
    const { response, scan } = await runLikersPage({
      db,
      Timestamp,
      viewerId: auth.uid,
      targetType: input.targetType,
      targetKey: likersTargetKey(input),
      cursor: input.cursor,
      timing,
      fetchCandidates: target.fetchCandidates,
      resolveVisible: likerResolver({
        getAll,
        db,
        viewerId: auth.uid,
        nowMs: timing.nowMs,
        surface: likerSurface,
        serverId: target.serverId ?? null,
        server: target.server ?? null,
      }),
      recheck: target.recheck ?? (async () => {}),
      ...(randomBytes ? { randomBytes } : {}),
    });
    if (scan.unstorable !== null) {
      // Malformed server data (an edge createdAt the cursor cannot store):
      // the page was cut back, or the list ended. Never the caller's input.
      logger?.warn?.("likers page ended before an unstorable position", {
        targetType: input.targetType,
        unstorable: scan.unstorable,
      });
    }
    return response;
  } catch (error) {
    return collapseContentRefusal(error);
  }
}

module.exports = {
  LIKERS_UNAVAILABLE_MESSAGE,
  LIKERS_UNIFORM_REFUSAL_CODES,
  collapseContentRefusal,
  plainGetAll,
  plainReader,
  serveLikersList,
};
