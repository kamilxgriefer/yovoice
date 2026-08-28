const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { Timestamp } = require("firebase-admin/firestore");

const { requireAuthentication } = require("../utils/auth");
const { db } = require("../utils/firestore");
const {
  ACTIVE_PREMIUM_STATUSES,
  deriveEffectivePremiumAccess,
  paidPremiumIsActive,
} = require("../utils/premium_access");

const REGION = "europe-west1";
const CREATOR_ACCOUNT_TYPES = new Set(["creator", "official"]);
const SAFE_DOCUMENT_ID = /^[A-Za-z0-9_-]{1,128}$/u;

function canonicalCreatorId(value) {
  return typeof value === "string" && value.length >= 1 &&
    value.length <= 128 && !value.includes("/");
}

function requireExactInput(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "A pinned Moment selection is required.");
  }
  const keys = Object.keys(data).sort();
  if (keys.length !== 1 || keys[0] !== "momentId") {
    throw new HttpsError(
      "invalid-argument",
      "Only momentId may be supplied when changing a pinned post.",
    );
  }
  if (data.momentId === null) return null;
  if (typeof data.momentId !== "string" ||
      !SAFE_DOCUMENT_ID.test(data.momentId)) {
    throw new HttpsError("invalid-argument", "The selected Voice Moment is invalid.");
  }
  return data.momentId;
}

function activeCreatorEntitlement(data, nowMs) {
  return paidPremiumIsActive(data, nowMs) &&
    data?.creatorEnabled === true &&
    data?.premiumIdentityEnabled === true;
}

function eligibleMoment(data, uid) {
  return data?.schemaVersion === 2 &&
    data?.authorId === uid &&
    data?.status === "published" &&
    data?.isPublished === true &&
    data?.isDeleted === false &&
    typeof data?.caption === "string" &&
    typeof data?.audioUrl === "string" && data.audioUrl.length > 0 &&
    Number.isInteger(data?.durationSeconds) &&
    data.durationSeconds >= 1 && data.durationSeconds <= 60 &&
    Number.isInteger(data?.likeCount) && data.likeCount >= 0 &&
    Number.isInteger(data?.commentCount) && data.commentCount >= 0;
}

const CREATOR_ELIGIBILITY_FIELDS = Object.freeze([
  "accountType",
  "banned",
  "deleted",
  "disabled",
  "role",
  "roleTransitionInProgress",
  "status",
]);

function creatorEligibilityChanged(before, after) {
  const oldData = before && typeof before === "object" ? before : {};
  const newData = after && typeof after === "object" ? after : {};
  return CREATOR_ELIGIBILITY_FIELDS.some(
    (field) => oldData[field] !== newData[field],
  );
}

function activeProfile(snapshot) {
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Your profile does not exist.");
  }
  const profile = snapshot.data() ?? {};
  if (profile.banned === true || profile.disabled === true ||
      profile.deleted === true || profile.status === "deleted") {
    throw new HttpsError(
      "permission-denied",
      "This account cannot manage Creator Studio posts.",
    );
  }
  return profile;
}

function activeCreatorProfile(snapshot) {
  const profile = activeProfile(snapshot);
  if (!CREATOR_ACCOUNT_TYPES.has(profile.accountType)) {
    throw new HttpsError(
      "failed-precondition",
      "A Creator account is required to pin a post.",
    );
  }
  return profile;
}

function isActiveCreatorProfile(snapshot) {
  if (!snapshot?.exists) return false;
  const profile = snapshot.data() ?? {};
  return profile.banned !== true && profile.disabled !== true &&
    profile.deleted !== true && profile.status !== "deleted" &&
    CREATOR_ACCOUNT_TYPES.has(profile.accountType);
}

function activeRoleTransition(profile) {
  return profile?.role === "user" &&
    profile.roleTransitionInProgress === true &&
    profile.banned !== true && profile.disabled !== true &&
    profile.deleted !== true && profile.status !== "deleted" &&
    !profile.authDeletedAt;
}

/**
 * Builds the server-authoritative pin mutation and cleanup handlers.
 *
 * `voiceMoments` stays canonical and immutable. The pin is a separate,
 * one-document projection keyed by creator uid; clients can read a known uid
 * but Firestore Rules deny both list and every direct write.
 */
function createPinnedPostsService({
  firestore,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
}) {
  if (!firestore || !TimestampImpl?.fromMillis) {
    throw new TypeError("firestore and Timestamp are required.");
  }

  async function setCreatorPinnedPost(request) {
    const auth = requireAuthentication(request);
    if (auth.token?.email_verified !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Verify your email before managing Creator Studio posts.",
      );
    }
    const momentId = requireExactInput(request.data);
    const nowMs = clock();
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    const now = TimestampImpl.fromMillis(nowMs);
    const uid = auth.uid;
    const pinRef = firestore.doc(`creatorPinnedPosts/${uid}`);
    const profileRef = firestore.doc(`users/${uid}`);
    const entitlementRef = firestore.doc(`entitlements/${uid}`);

    return firestore.runTransaction(async (transaction) => {
      const references = [profileRef, entitlementRef, pinRef];
      const momentRef = momentId === null
        ? null
        : firestore.doc(`voiceMoments/${momentId}`);
      if (momentRef) references.push(momentRef);
      const snapshots = typeof transaction.getAll === "function"
        ? await transaction.getAll(...references)
        : await Promise.all(references.map((reference) => transaction.get(reference)));
      const [profileSnapshot, entitlementSnapshot, pinSnapshot] = snapshots;

      if (momentId === null) {
        activeProfile(profileSnapshot);
        if (pinSnapshot.exists) transaction.delete(pinRef);
        return { pinned: false, momentId: null };
      }

      const profile = activeCreatorProfile(profileSnapshot);
      const entitlement = entitlementSnapshot.exists
        ? (entitlementSnapshot.data() ?? {})
        : null;
      const access = deriveEffectivePremiumAccess({
        user: profile,
        tokenRole: auth.token?.role,
        entitlement,
        now: nowMs,
        requireTokenRole: true,
      });
      if (!access.creatorEnabled) {
        throw new HttpsError(
          "failed-precondition",
          "Active Premium Creator access is required.",
        );
      }

      const momentSnapshot = snapshots[3];
      if (!momentSnapshot?.exists || !eligibleMoment(momentSnapshot.data(), uid)) {
        throw new HttpsError(
          "failed-precondition",
          "Only one of your published Voice Moments can be pinned.",
        );
      }

      const previous = pinSnapshot.exists ? (pinSnapshot.data() ?? {}) : {};
      const pinnedAt = previous.momentId === momentId && previous.pinnedAt
        ? previous.pinnedAt
        : now;
      transaction.set(pinRef, {
        schemaVersion: 1,
        creatorId: uid,
        momentId,
        pinnedAt,
        updatedAt: now,
      });
      return { pinned: true, momentId };
    });
  }

  async function clearPinForIneligibleMoment(momentId) {
    if (typeof momentId !== "string" || !SAFE_DOCUMENT_ID.test(momentId)) {
      return { cleared: false };
    }
    const momentRef = firestore.doc(`voiceMoments/${momentId}`);
    return firestore.runTransaction(async (transaction) => {
      const momentSnapshot = await transaction.get(momentRef);
      const moment = momentSnapshot.exists ? (momentSnapshot.data() ?? {}) : null;
      const creatorId = typeof moment?.authorId === "string" && moment.authorId
        ? moment.authorId
        : null;
      // A deleted document has no author id. Its previous owner must be passed
      // by the trigger so this helper's explicit cleanup overload can find it.
      if (!canonicalCreatorId(creatorId) || eligibleMoment(moment, creatorId)) {
        return { cleared: false };
      }
      const pinRef = firestore.doc(`creatorPinnedPosts/${creatorId}`);
      const pinSnapshot = await transaction.get(pinRef);
      if (!pinSnapshot.exists || pinSnapshot.data()?.momentId !== momentId) {
        return { cleared: false };
      }
      transaction.delete(pinRef);
      return { cleared: true, creatorId };
    });
  }

  async function clearDeletedMomentPin(momentId, creatorId) {
    if (!SAFE_DOCUMENT_ID.test(momentId) ||
        !canonicalCreatorId(creatorId)) {
      return { cleared: false };
    }
    const pinRef = firestore.doc(`creatorPinnedPosts/${creatorId}`);
    return firestore.runTransaction(async (transaction) => {
      const [momentSnapshot, pinSnapshot] = typeof transaction.getAll === "function"
        ? await transaction.getAll(
          firestore.doc(`voiceMoments/${momentId}`),
          pinRef,
        )
        : await Promise.all([
          transaction.get(firestore.doc(`voiceMoments/${momentId}`)),
          transaction.get(pinRef),
        ]);
      // A delayed trigger must never clear a newly republished eligible item.
      if (momentSnapshot.exists && eligibleMoment(momentSnapshot.data(), creatorId)) {
        return { cleared: false };
      }
      if (!pinSnapshot.exists || pinSnapshot.data()?.momentId !== momentId) {
        return { cleared: false };
      }
      transaction.delete(pinRef);
      return { cleared: true, creatorId };
    });
  }

  async function clearPinForIneligibleCreator(creatorId) {
    if (!canonicalCreatorId(creatorId)) {
      return { cleared: false };
    }
    const pinRef = firestore.doc(`creatorPinnedPosts/${creatorId}`);
    return firestore.runTransaction(async (transaction) => {
      const references = [
        pinRef,
        firestore.doc(`users/${creatorId}`),
        firestore.doc(`entitlements/${creatorId}`),
      ];
      const [pinSnapshot, profileSnapshot, entitlementSnapshot] =
        typeof transaction.getAll === "function"
          ? await transaction.getAll(...references)
          : await Promise.all(
            references.map((reference) => transaction.get(reference)),
          );
      const entitlement = entitlementSnapshot.exists
        ? (entitlementSnapshot.data() ?? {})
        : null;
      const profile = profileSnapshot.exists
        ? (profileSnapshot.data() ?? {})
        : null;
      // A privileged-to-privileged role change temporarily uses `role=user`
      // as a fail-closed Auth/mirror interlock. Do not treat that short-lived
      // state as a real demotion and irreversibly delete Creator data. Missing
      // and inactive/deleted profiles deliberately bypass this deferral so
      // their orphaned pins are still removed.
      if (profileSnapshot.exists && activeRoleTransition(profile)) {
        return { cleared: false, deferred: true };
      }
      const access = deriveEffectivePremiumAccess({
        user: profile,
        entitlement,
        now: clock(),
      });
      if (isActiveCreatorProfile(profileSnapshot) && access.creatorEnabled) {
        return { cleared: false };
      }
      let cleared = false;
      if (pinSnapshot.exists) {
        transaction.delete(pinRef);
        cleared = true;
      }
      let creatorModeReset = false;
      if (profileSnapshot.exists &&
          profile?.accountType === "creator" &&
          !access.creatorEnabled) {
        transaction.set(
          firestore.doc(`users/${creatorId}`),
          { accountType: "personal" },
          { merge: true },
        );
        creatorModeReset = true;
      }
      if (!cleared && !creatorModeReset) return { cleared: false };
      return { cleared, creatorId };
    });
  }

  return Object.freeze({
    clearDeletedMomentPin,
    clearPinForIneligibleCreator,
    clearPinForIneligibleMoment,
    setCreatorPinnedPost,
  });
}

const service = createPinnedPostsService({ firestore: db });

const setCreatorPinnedPost = onCall(
  { region: REGION, enforceAppCheck: false },
  service.setCreatorPinnedPost,
);

async function handlePinnedMomentEligibilityChanged(
  event,
  pinnedService = service,
) {
    const after = event.data?.after;
    const before = event.data?.before;
    const afterData = after?.exists ? (after.data() ?? {}) : null;
    const beforeData = before?.exists ? (before.data() ?? {}) : null;
    const beforeCreatorId = typeof beforeData?.authorId === "string"
      ? beforeData.authorId
      : null;
    const afterCreatorId = typeof afterData?.authorId === "string"
      ? afterData.authorId
      : null;
    const outcomes = [];
    // Clear the old author's projection even if a trusted migration changes
    // authorId and leaves an otherwise published document behind.
    if (beforeCreatorId && beforeCreatorId !== afterCreatorId) {
      outcomes.push(
        await pinnedService.clearDeletedMomentPin(
          event.params.momentId,
          beforeCreatorId,
        ),
      );
    }
    if (afterCreatorId &&
        !(after?.exists && eligibleMoment(afterData, afterCreatorId))) {
      outcomes.push(
        await pinnedService.clearDeletedMomentPin(
          event.params.momentId,
          afterCreatorId,
        ),
      );
    }
    return { cleared: outcomes.some((outcome) => outcome.cleared === true) };
}

const onPinnedMomentEligibilityChanged = onDocumentWritten(
  {
    region: REGION,
    document: "voiceMoments/{momentId}",
    retry: true,
  },
  handlePinnedMomentEligibilityChanged,
);

const onPinnedCreatorEntitlementChanged = onDocumentWritten(
  {
    region: REGION,
    document: "entitlements/{creatorId}",
    retry: true,
  },
  (event) => service.clearPinForIneligibleCreator(event.params.creatorId),
);

function handlePinnedCreatorProfileChanged(event, pinnedService = service) {
  const before = event.data?.before;
  const after = event.data?.after;
  const beforeData = before?.exists ? (before.data() ?? {}) : null;
  const afterData = after?.exists ? (after.data() ?? {}) : null;
  if (after?.exists && activeRoleTransition(afterData)) {
    return { cleared: false, deferred: true };
  }
  if (!creatorEligibilityChanged(beforeData, afterData)) {
    return { cleared: false, skipped: true };
  }
  return pinnedService.clearPinForIneligibleCreator(event.params.creatorId);
}

const onPinnedCreatorProfileChanged = onDocumentWritten(
  {
    region: REGION,
    document: "users/{creatorId}",
    retry: true,
  },
  handlePinnedCreatorProfileChanged,
);

module.exports = {
  ACTIVE_PREMIUM_STATUSES,
  activeCreatorEntitlement,
  createPinnedPostsService,
  creatorEligibilityChanged,
  eligibleMoment,
  handlePinnedCreatorProfileChanged,
  handlePinnedMomentEligibilityChanged,
  onPinnedCreatorEntitlementChanged,
  onPinnedCreatorProfileChanged,
  onPinnedMomentEligibilityChanged,
  setCreatorPinnedPost,
};
