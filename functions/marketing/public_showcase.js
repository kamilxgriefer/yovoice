// Consent-backed public marketing showcase.
//
// `publicShowcase/live` is intentionally world-readable so the unauthenticated
// marketing site can render it. The scheduler therefore publishes a tiny,
// exact projection and never copies identifiers, usernames, email addresses,
// profile photos, staff roles, presence timestamps or last-seen values.
//
// Presence in `users` is client-written and has no disconnect authority. Even
// when it is fresh it must not be presented as "online now". A user who opts
// into `showActivityOnWebsite` can only receive the honest,
// weaker `activeRecently` label. True online status needs an authoritative
// disconnect-aware source before it may be added here.

const { createHash } = require("node:crypto");
const { logger } = require("firebase-functions/v2");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { getAuth } = require("firebase-admin/auth");
const { Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const { normalizeProfileVisibility } = require("../profile/profile_visibility");

const REGION = "europe-west1";
const MARKETING_CONSENTS_COLLECTION = "marketingConsents";
const CLUB_MARKETING_CONSENTS_COLLECTION = "clubMarketingConsents";
const PUBLIC_SHOWCASE_COLLECTION = "publicShowcase";
const PUBLIC_SHOWCASE_DOCUMENT = "live";
const PRIVATE_SHOWCASE_CONTROL_COLLECTION = "privateShowcaseControl";
const PUBLIC_SHOWCASE_SCHEMA_VERSION = 1;
const CONSENT_SCHEMA_VERSION = 1;
const MAX_PERSON_CONSENT_SCAN = 200;
const MAX_CLUB_CONSENT_SCAN = 100;
const MAX_PUBLIC_PEOPLE = 4;
const MAX_PUBLIC_CLUBS = 4;
const RECENT_ACTIVITY_SECONDS = 90;
const MIN_ACTIVITY_COHORT = 3;
const SHOWCASE_VALIDITY_SECONDS = 3 * 60;
const ACCOUNT_TYPES = new Set(["personal", "creator", "official"]);

class PublicShowcaseError extends Error {
  constructor(message) {
    super(message);
    this.name = "PublicShowcaseError";
  }
}

function exactKeys(value, keys) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const actual = Object.keys(value).sort();
  return actual.length === keys.length &&
    actual.every((key, index) => key === [...keys].sort()[index]);
}

function timestampMillis(value) {
  if (value && typeof value.toMillis === "function") {
    const millis = value.toMillis();
    return Number.isFinite(millis) ? millis : null;
  }
  if (value instanceof Date) {
    const millis = value.getTime();
    return Number.isFinite(millis) ? millis : null;
  }
  return null;
}

function safeDocumentId(value) {
  return typeof value === "string" &&
    value.length >= 1 &&
    value.length <= 128 &&
    !value.includes("/")
    ? value
    : null;
}

function safeText(value, maximum) {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, maximum);
}

function boundedConsentDocuments(snapshot, maximum, label) {
  if (!snapshot || !Array.isArray(snapshot.docs)) {
    throw new PublicShowcaseError(`${label} consent query returned no documents.`);
  }
  // The query intentionally asks for maximum + 1 so an operator can observe
  // saturation, but a 201st valid opt-in must never take the entire public
  // showcase offline. Publishing a bounded subset cannot leak a non-consenting
  // account; it only defers selection fairness beyond the current scan cap.
  // Availability therefore wins over aborting every future scheduler run.
  return snapshot.docs.slice(0, maximum);
}

function validMarketingConsent(value) {
  return exactKeys(value, [
    "schemaVersion",
    "showProfileOnWebsite",
    "showActivityOnWebsite",
    "updatedAt",
  ]) &&
    value.schemaVersion === CONSENT_SCHEMA_VERSION &&
    typeof value.showProfileOnWebsite === "boolean" &&
    typeof value.showActivityOnWebsite === "boolean" &&
    (!value.showActivityOnWebsite || value.showProfileOnWebsite) &&
    timestampMillis(value.updatedAt) !== null;
}

function validClubMarketingConsent(value) {
  return exactKeys(value, [
    "schemaVersion",
    "clubId",
    "ownerId",
    "showOnWebsite",
    "updatedAt",
  ]) &&
    value.schemaVersion === CONSENT_SCHEMA_VERSION &&
    safeDocumentId(value.clubId) !== null &&
    safeDocumentId(value.ownerId) !== null &&
    typeof value.showOnWebsite === "boolean" &&
    timestampMillis(value.updatedAt) !== null;
}

function derivePublicPerson({ uid, consent, profile, user, authUser }, nowMillis) {
  if (!safeDocumentId(uid) || !validMarketingConsent(consent) ||
      consent.showProfileOnWebsite !== true) {
    return null;
  }
  if (!profile || profile.uid !== uid || profile.schemaVersion !== 1) {
    return null;
  }
  if (!authUser || authUser.uid !== uid || authUser.disabled === true ||
      !user || user.banned === true || user.disabled === true ||
      user.deleted === true || user.status === "deleted" ||
      user.roleTransitionInProgress === true ||
      normalizeProfileVisibility(user.profileVisibility) !== "public" ||
      user.role !== "user") {
    return null;
  }

  const displayName = safeText(profile.displayName, 80);
  const accountType = safeText(profile.accountType, 24);
  if (!displayName || !ACCOUNT_TYPES.has(accountType)) return null;

  // Only the heartbeat timestamp can support the deliberately weak
  // "Active recently" label. `lastSeen` has separate semantics and must not
  // silently rescue a stale heartbeat.
  const presenceMillis = timestampMillis(user.presenceUpdatedAt);
  const ageMillis = presenceMillis === null ? null : nowMillis - presenceMillis;
  const activity = consent.showActivityOnWebsite === true &&
      user.isOnline === true &&
      ageMillis !== null &&
      ageMillis >= 0 &&
      ageMillis < RECENT_ACTIVITY_SECONDS * 1000
    ? "activeRecently"
    : "undisclosed";

  return {
    _rotationKey: uid,
    _activityValidUntilMillis: activity === "activeRecently"
      ? presenceMillis + (RECENT_ACTIVITY_SECONDS * 1000)
      : null,
    displayName,
    accountType,
    activity,
  };
}

function derivePublicClub({ clubId, consent, club }) {
  if (!safeDocumentId(clubId) || !validClubMarketingConsent(consent) ||
      consent.clubId !== clubId || consent.showOnWebsite !== true || !club ||
      consent.ownerId !== club.ownerId) {
    return null;
  }
  if (club.type !== "community" || club.privacy !== "public" ||
      club.status !== "active" || club.deletionInProgress === true) {
    return null;
  }
  const name = safeText(club.name, 80);
  const memberCount = club.memberCount;
  if (!name || !Number.isSafeInteger(memberCount) || memberCount < 0) {
    return null;
  }
  return { _rotationKey: clubId, name, memberCount };
}

function rotationScore(key, bucket) {
  return createHash("sha256")
    .update(`${bucket}:${key}`, "utf8")
    .digest("hex");
}

function rotatingRows(rows, maximum, nowMillis) {
  const bucket = Math.floor(nowMillis / (60 * 1000));
  return rows
    .filter(Boolean)
    .sort((left, right) => rotationScore(left._rotationKey, bucket)
      .localeCompare(rotationScore(right._rotationKey, bucket)))
    .slice(0, maximum);
}

function stripPrivateSelectionFields(row) {
  const {
    _rotationKey: _key,
    _activityValidUntilMillis: _activityExpiry,
    ...published
  } = row;
  return published;
}

function rotatingPublicRows(rows, maximum, nowMillis) {
  return rotatingRows(rows, maximum, nowMillis)
    .map(stripPrivateSelectionFields);
}

async function loadPeopleFromFirestore(database = db, authClient = getAuth()) {
  const consentSnapshot = await database
    .collection(MARKETING_CONSENTS_COLLECTION)
    .where("showProfileOnWebsite", "==", true)
    .limit(MAX_PERSON_CONSENT_SCAN + 1)
    .get();
  const consents = boundedConsentDocuments(
    consentSnapshot,
    MAX_PERSON_CONSENT_SCAN,
    "Profile",
  )
    .map((document) => ({
      uid: safeDocumentId(document.id),
      consent: document.data() ?? {},
    }))
    .filter(({ uid, consent }) => uid !== null && validMarketingConsent(consent));
  if (consents.length === 0) return [];

  const references = consents.flatMap(({ uid }) => [
    database.collection("publicProfiles").doc(uid),
    database.collection("users").doc(uid),
  ]);
  const snapshots = await database.getAll(...references);
  const authUsers = new Map();
  for (let start = 0; start < consents.length; start += 100) {
    const response = await authClient.getUsers(
      consents.slice(start, start + 100).map(({ uid }) => ({ uid })),
    );
    for (const record of response.users) {
      authUsers.set(record.uid, {
        uid: record.uid,
        disabled: record.disabled === true,
      });
    }
  }
  return consents.map(({ uid, consent }, index) => ({
    uid,
    consent,
    profile: snapshots[index * 2]?.exists
      ? (snapshots[index * 2].data() ?? {})
      : null,
    user: snapshots[(index * 2) + 1]?.exists
      ? (snapshots[(index * 2) + 1].data() ?? {})
      : null,
    authUser: authUsers.get(uid) ?? null,
  }));
}

async function loadClubsFromFirestore(database = db) {
  const consentSnapshot = await database
    .collection(CLUB_MARKETING_CONSENTS_COLLECTION)
    .where("showOnWebsite", "==", true)
    .limit(MAX_CLUB_CONSENT_SCAN + 1)
    .get();
  const consents = boundedConsentDocuments(
    consentSnapshot,
    MAX_CLUB_CONSENT_SCAN,
    "Club",
  )
    .map((document) => ({
      clubId: safeDocumentId(document.id),
      consent: document.data() ?? {},
    }))
    .filter(({ clubId, consent }) =>
      clubId !== null && validClubMarketingConsent(consent));
  if (consents.length === 0) return [];

  const snapshots = await database.getAll(...consents.map(({ clubId }) =>
    database.collection("clubs").doc(clubId)));
  return consents.map(({ clubId, consent }, index) => ({
    clubId,
    consent,
    club: snapshots[index]?.exists ? (snapshots[index].data() ?? {}) : null,
  }));
}

async function computePublicShowcase({
  nowMillis = Date.now(),
  loadPeople = () => loadPeopleFromFirestore(),
  loadClubs = () => loadClubsFromFirestore(),
} = {}) {
  if (!Number.isFinite(nowMillis)) {
    throw new PublicShowcaseError("The showcase clock is invalid.");
  }
  const outcomes = await Promise.allSettled([loadPeople(), loadClubs()]);
  const failure = outcomes.find((outcome) => outcome.status === "rejected");
  if (failure) throw failure.reason;

  const [peopleSources, clubSources] = outcomes.map((outcome) => outcome.value);
  if (!Array.isArray(peopleSources) || !Array.isArray(clubSources)) {
    throw new PublicShowcaseError("A showcase source returned an invalid shape.");
  }

  const derivedPeople = peopleSources
    .map((source) => derivePublicPerson(source, nowMillis))
    .filter(Boolean);
  if (derivedPeople.filter(({ activity }) =>
    activity === "activeRecently").length < MIN_ACTIVITY_COHORT) {
    for (const person of derivedPeople) {
      person.activity = "undisclosed";
      person._activityValidUntilMillis = null;
    }
  }
  const selectedPeople = rotatingRows(
    derivedPeople,
    MAX_PUBLIC_PEOPLE,
    nowMillis,
  );
  if (selectedPeople.filter(({ activity }) =>
    activity === "activeRecently").length < MIN_ACTIVITY_COHORT) {
    for (const person of selectedPeople) {
      person.activity = "undisclosed";
      person._activityValidUntilMillis = null;
    }
  }
  const people = selectedPeople.map(stripPrivateSelectionFields);
  const clubs = rotatingPublicRows(
    clubSources.map(derivePublicClub),
    MAX_PUBLIC_CLUBS,
    nowMillis,
  );

  const selectedActivityExpiries = selectedPeople
    .map(({ _activityValidUntilMillis }) => _activityValidUntilMillis)
    .filter((value) => Number.isFinite(value));
  const activityValidUntilMillis = selectedActivityExpiries.length === 0
    ? nowMillis + (RECENT_ACTIVITY_SECONDS * 1000)
    : Math.min(...selectedActivityExpiries);

  return {
    schemaVersion: PUBLIC_SHOWCASE_SCHEMA_VERSION,
    people,
    clubs,
    generatedAt: Timestamp.fromMillis(nowMillis),
    activityValidUntil: Timestamp.fromMillis(
      activityValidUntilMillis,
    ),
    validUntil: Timestamp.fromMillis(
      nowMillis + (SHOWCASE_VALIDITY_SECONDS * 1000),
    ),
  };
}

async function publishPublicShowcase({
  nowMillis = Date.now(),
  loadPeople = () => loadPeopleFromFirestore(),
  loadClubs = () => loadClubsFromFirestore(),
  writeShowcase = null,
  readPrivacyGeneration = null,
} = {}) {
  const controlRef = db
    .collection(PRIVATE_SHOWCASE_CONTROL_COLLECTION)
    .doc(PUBLIC_SHOWCASE_DOCUMENT);
  const readGeneration = readPrivacyGeneration ?? (async () => {
    const snapshot = await controlRef.get();
    const value = snapshot.data()?.privacyGeneration;
    return Number.isSafeInteger(value) && value >= 0 ? value : 0;
  });
  const privacyGeneration = await readGeneration();
  const showcase = await computePublicShowcase({
    nowMillis,
    loadPeople,
    loadClubs,
  });
  if (writeShowcase) {
    await writeShowcase(showcase);
  } else {
    const showcaseRef = db
      .collection(PUBLIC_SHOWCASE_COLLECTION)
      .doc(PUBLIC_SHOWCASE_DOCUMENT);
    await db.runTransaction(async (transaction) => {
      const control = await transaction.get(controlRef);
      const value = control.data()?.privacyGeneration;
      const currentGeneration = Number.isSafeInteger(value) && value >= 0
        ? value
        : 0;
      if (currentGeneration !== privacyGeneration) {
        throw new PublicShowcaseError(
          "Profile privacy changed while the showcase was being built; refusing a stale publication.",
        );
      }
      transaction.set(showcaseRef, showcase);
    });
  }
  return showcase;
}

const publishPublicShowcaseSchedule = onSchedule(
  {
    region: REGION,
    schedule: "every 1 minutes",
    timeZone: "UTC",
    maxInstances: 1,
    timeoutSeconds: 120,
  },
  async () => {
    const showcase = await publishPublicShowcase();
    logger.info("public showcase published", {
      people: showcase.people.length,
      clubs: showcase.clubs.length,
      validUntil: showcase.validUntil.toDate().toISOString(),
    });
  },
);

module.exports = {
  CLUB_MARKETING_CONSENTS_COLLECTION,
  CONSENT_SCHEMA_VERSION,
  MARKETING_CONSENTS_COLLECTION,
  MAX_CLUB_CONSENT_SCAN,
  MAX_PERSON_CONSENT_SCAN,
  MAX_PUBLIC_CLUBS,
  MAX_PUBLIC_PEOPLE,
  MIN_ACTIVITY_COHORT,
  PUBLIC_SHOWCASE_COLLECTION,
  PUBLIC_SHOWCASE_DOCUMENT,
  PUBLIC_SHOWCASE_SCHEMA_VERSION,
  PRIVATE_SHOWCASE_CONTROL_COLLECTION,
  PublicShowcaseError,
  RECENT_ACTIVITY_SECONDS,
  REGION,
  SHOWCASE_VALIDITY_SECONDS,
  boundedConsentDocuments,
  computePublicShowcase,
  derivePublicClub,
  derivePublicPerson,
  loadClubsFromFirestore,
  loadPeopleFromFirestore,
  publishPublicShowcase,
  publishPublicShowcaseSchedule,
  rotatingRows,
  rotatingPublicRows,
  validClubMarketingConsent,
  validMarketingConsent,
};
