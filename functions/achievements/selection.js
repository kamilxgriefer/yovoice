const { buildUserAchievementProjection, availableTitleIds, normalizeProgress } =
  require("./model");
const { isValidOpaqueUid } = require("./identity");

class AchievementSelectionError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "AchievementSelectionError";
    this.code = code;
  }
}

function normalizeSelectionUid(value) {
  if (!isValidOpaqueUid(value)) {
    throw new AchievementSelectionError("invalid-argument", "The user id is invalid.");
  }
  return value;
}

// This is deliberately not an onCall export. The future callable wrapper must
// pass request.auth.uid as uid; callers never choose whose title is modified.
async function selectAchievementTitle({
  repository,
  uid: uidInput,
  titleId: titleInput,
  clock = () => new Date(),
}) {
  if (!repository || typeof repository.runTransaction !== "function") {
    throw new TypeError("An achievement transaction repository is required.");
  }
  const uid = normalizeSelectionUid(uidInput);
  const titleId = titleInput === null
    ? null
    : typeof titleInput === "string"
      ? titleInput.trim()
      : undefined;
  if (titleId === undefined || (titleId !== null && !titleId)) {
    throw new AchievementSelectionError(
      "invalid-argument",
      "A title id or null is required.",
    );
  }
  const now = clock();
  if (!(now instanceof Date) || !Number.isFinite(now.getTime())) {
    throw new TypeError("The selection clock returned an invalid date.");
  }

  return repository.runTransaction(async (transaction) => {
    const user = await transaction.getUser(uid);
    if (!user) {
      throw new AchievementSelectionError("not-found", "The user profile was not found.");
    }
    if (user.banned === true || user.disabled === true || user.deleted === true ||
        user.status === "deleted") {
      throw new AchievementSelectionError(
        "permission-denied",
        "An active user profile is required.",
      );
    }
    const storedProgress = await transaction.getProgress(uid);
    const progress = normalizeProgress(storedProgress, { legacyUser: user });
    if (titleId !== null && !availableTitleIds(progress).includes(titleId)) {
      throw new AchievementSelectionError(
        "failed-precondition",
        "The selected achievement is not unlocked.",
      );
    }
    if (progress.selectedTitleId === titleId) {
      return { outcome: "unchanged", selectedTitleId: titleId };
    }
    progress.selectedTitleId = titleId;
    const stored = { ...progress, updatedAt: now };
    await transaction.setProgress(uid, stored);
    await transaction.setUserProjection(
      uid,
      buildUserAchievementProjection(stored, now),
    );
    return { outcome: "updated", selectedTitleId: titleId };
  });
}

module.exports = {
  AchievementSelectionError,
  selectAchievementTitle,
};
