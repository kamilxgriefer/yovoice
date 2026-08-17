const { onCall, HttpsError } = require("firebase-functions/v2/https");

const { FirestoreAchievementRepository } = require("./firestore_repository");
const {
  AchievementSelectionError,
  selectAchievementTitle,
} = require("./selection");

const REGION = "europe-west1";
const CALLABLE_OPTIONS = Object.freeze({
  region: REGION,
  // Web App Check is not enforceable until the web client has a real
  // reCAPTCHA key. Auth binding and server-verified unlocks remain mandatory.
  enforceAppCheck: false,
});

function createSelectMyAchievementTitleHandler({
  repository = null,
  clock = () => new Date(),
} = {}) {
  return async function selectMyAchievementTitleHandler(request) {
    const uid = request?.auth?.uid;
    if (typeof uid !== "string") {
      throw new HttpsError("unauthenticated", "Authentication is required.");
    }
    const data = request?.data;
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      throw new HttpsError("invalid-argument", "A title selection is required.");
    }
    // The client has always sent `titleId` PLUS a `requestId`, while this
    // allowlist accepted the single key `titleId` and nothing else. Every call
    // therefore failed `invalid-argument`, which is not in the client's
    // fallback set, so it was rethrown rather than degrading — server-side
    // title selection was dead in production. `requestId` is accepted and
    // validated here, but carries no idempotency semantics: unlike
    // `moderateReport`, selection advances no state machine and simply sets
    // `selectedTitleId`, so replaying it converges on the same state.
    const keys = Object.keys(data);
    if (!keys.includes("titleId") ||
        keys.some((key) => key !== "titleId" && key !== "requestId")) {
      throw new HttpsError(
        "invalid-argument",
        "Only titleId and requestId may be supplied.",
      );
    }
    const titleId = data.titleId;
    if (titleId !== null && typeof titleId !== "string") {
      throw new HttpsError("invalid-argument", "titleId must be text or null.");
    }
    if (keys.includes("requestId") &&
        (typeof data.requestId !== "string" || !data.requestId.trim() ||
         data.requestId.length > 64)) {
      throw new HttpsError(
        "invalid-argument",
        "requestId must be text of at most 64 characters.",
      );
    }

    try {
      return await selectAchievementTitle({
        repository: repository ?? new FirestoreAchievementRepository(),
        uid,
        titleId,
        clock,
      });
    } catch (error) {
      if (error instanceof AchievementSelectionError) {
        throw new HttpsError(error.code, error.message);
      }
      throw error;
    }
  };
}

const selectMyAchievementTitle = onCall(
  CALLABLE_OPTIONS,
  createSelectMyAchievementTitleHandler(),
);

module.exports = {
  CALLABLE_OPTIONS,
  REGION,
  createSelectMyAchievementTitleHandler,
  selectMyAchievementTitle,
};
