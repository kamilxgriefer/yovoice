const { FieldPath } = require("firebase-admin/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const { isValidOpaqueUid } = require("./identity");
const {
  buildUserAchievementProjection,
  legacyProgressFromUser,
} = require("./model");
const { getDefaultAchievementRuntime } = require("./runtime");

const REGION = "europe-west1";
const MIGRATION_SCHEMA_VERSION = 1;
const DEFAULT_USERS_PER_RUN = 5;
const DEFAULT_EVENTS_PER_PAGE = 100;
const MAX_USERS_PER_RUN = 25;
const MAX_EVENTS_PER_PAGE = 250;
const GLOBAL_STATE_PATH = "achievementMigrationRuns/achievementsV1";

class AchievementMigrationError extends Error {
  constructor(message) {
    super(message);
    this.name = "AchievementMigrationError";
  }
}

function dateFrom(value, label) {
  const date = value instanceof Date
    ? value
    : typeof value?.toDate === "function"
      ? value.toDate()
      : null;
  if (!(date instanceof Date) || !Number.isFinite(date.getTime())) {
    throw new AchievementMigrationError(`${label} is invalid.`);
  }
  return new Date(date.getTime());
}

function requireBound(value, minimum, maximum, label) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new AchievementMigrationError(`${label} is outside its safe bound.`);
  }
  return value;
}

function normalizeEvidenceCursor(raw, providerCount) {
  if (raw === null || raw === undefined) {
    return { providerIndex: 0, providerCursor: null };
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw) ||
      !Number.isSafeInteger(raw.providerIndex) || raw.providerIndex < 0 ||
      raw.providerIndex > providerCount ||
      !(raw.providerCursor === null ||
        (typeof raw.providerCursor === "object" &&
         !Array.isArray(raw.providerCursor)))) {
    throw new AchievementMigrationError("The evidence cursor is malformed.");
  }
  return {
    providerIndex: raw.providerIndex,
    providerCursor: raw.providerCursor ?? null,
  };
}

function createBoundedCanonicalEvidenceSource({ providers = [] } = {}) {
  if (!Array.isArray(providers) || providers.some((provider) =>
    !provider || typeof provider.readPage !== "function")) {
    throw new TypeError("Canonical evidence providers must expose readPage().");
  }
  return Object.freeze({
    async readPage({ uid, cursor = null, limit = DEFAULT_EVENTS_PER_PAGE }) {
      if (!isValidOpaqueUid(uid)) {
        throw new AchievementMigrationError("The migration user id is invalid.");
      }
      requireBound(limit, 1, MAX_EVENTS_PER_PAGE, "Evidence page size");
      const normalized = normalizeEvidenceCursor(cursor, providers.length);
      if (normalized.providerIndex === providers.length) {
        return { events: [], cursor: normalized, done: true };
      }
      const provider = providers[normalized.providerIndex];
      const page = await provider.readPage({
        uid,
        cursor: normalized.providerCursor,
        limit,
      });
      if (!page || !Array.isArray(page.events) || page.events.length > limit ||
          typeof page.done !== "boolean" ||
          !(page.cursor === null || page.cursor === undefined ||
            (typeof page.cursor === "object" && !Array.isArray(page.cursor)))) {
        throw new AchievementMigrationError(
          "A canonical evidence provider exceeded its contract.",
        );
      }
      const next = page.done
        ? { providerIndex: normalized.providerIndex + 1, providerCursor: null }
        : { providerIndex: normalized.providerIndex, providerCursor: page.cursor ?? null };
      return {
        events: page.events,
        cursor: next,
        done: next.providerIndex === providers.length,
      };
    },
  });
}

class FirestoreAchievementMigrationStore {
  constructor({ db = null } = {}) {
    this.db = db;
  }

  database() {
    return this.db ?? require("../utils/firestore").db;
  }

  async loadState() {
    const snapshot = await this.database().doc(GLOBAL_STATE_PATH).get();
    if (!snapshot.exists) {
      return { afterUid: null, currentUid: null, complete: false };
    }
    const data = snapshot.data() ?? {};
    const afterUid = data.afterUid === null || data.afterUid === undefined
      ? null
      : data.afterUid;
    const currentUid = data.currentUid === null || data.currentUid === undefined
      ? null
      : data.currentUid;
    if (data.schemaVersion !== MIGRATION_SCHEMA_VERSION ||
        (afterUid !== null && !isValidOpaqueUid(afterUid)) ||
        (currentUid !== null && !isValidOpaqueUid(currentUid)) ||
        typeof data.complete !== "boolean") {
      throw new AchievementMigrationError("Stored migration state is malformed.");
    }
    return { afterUid, currentUid, complete: data.complete };
  }

  async saveState(state, now) {
    await this.database().doc(GLOBAL_STATE_PATH).set({
      schemaVersion: MIGRATION_SCHEMA_VERSION,
      afterUid: state.afterUid ?? null,
      currentUid: state.currentUid ?? null,
      complete: state.complete === true,
      updatedAt: dateFrom(now, "Migration state timestamp"),
    });
  }

  async nextUser(afterUid = null) {
    let query = this.database().collection("users")
      .orderBy(FieldPath.documentId())
      .limit(1);
    if (afterUid !== null) {
      if (!isValidOpaqueUid(afterUid)) {
        throw new AchievementMigrationError("The user cursor is invalid.");
      }
      query = query.startAfter(afterUid);
    }
    const snapshot = await query.get();
    if (snapshot.empty) return null;
    const document = snapshot.docs[0];
    return { uid: document.id, user: document.data() ?? {} };
  }

  async user(uid) {
    if (!isValidOpaqueUid(uid)) {
      throw new AchievementMigrationError("The migration user id is invalid.");
    }
    const snapshot = await this.database().collection("users").doc(uid).get();
    return snapshot.exists ? { uid, user: snapshot.data() ?? {} } : null;
  }

  async beginUser({ uid, user, now }) {
    if (!isValidOpaqueUid(uid) || !user || typeof user !== "object") {
      throw new AchievementMigrationError("A canonical migration user is required.");
    }
    const database = this.database();
    const migrationRef = database.collection("achievementMigrations").doc(uid);
    const progressRef = database.collection("achievementProgress").doc(uid);
    const userRef = database.collection("users").doc(uid);
    return database.runTransaction(async (transaction) => {
      const [migrationSnapshot, canonicalUserSnapshot] =
        typeof transaction.getAll === "function"
          ? await transaction.getAll(migrationRef, userRef)
          : await Promise.all([
              transaction.get(migrationRef),
              transaction.get(userRef),
            ]);
      if (!canonicalUserSnapshot.exists) {
        return { outcome: "missing", evidenceCursor: null };
      }
      const migration = migrationSnapshot.exists
        ? migrationSnapshot.data() ?? {}
        : null;
      if (migration) {
        if (migration.schemaVersion !== MIGRATION_SCHEMA_VERSION ||
            migration.uid !== uid || migration.bootstrapCompleted !== true) {
          throw new AchievementMigrationError(
            "Stored user migration state is malformed.",
          );
        }
        return {
          outcome: "existing",
          evidenceCursor: migration.evidenceCursor ?? null,
          evidenceEventCount: migration.evidenceEventCount ?? 0,
        };
      }

      // Existing flat counters, title arrays and any pre-cutover progress are
      // not authority. Preserve legacy claims only in the private audit fields
      // while verified state starts at zero and is rebuilt from source events.
      const canonicalUser = canonicalUserSnapshot.data() ?? {};
      const progress = legacyProgressFromUser(canonicalUser);
      const timestamp = dateFrom(now, "Migration timestamp");
      transaction.set(progressRef, { ...progress, updatedAt: timestamp });
      transaction.set(userRef, {
        ...buildUserAchievementProjection(progress, timestamp),
        achievementVerificationStatus: "reconciling",
      }, { merge: true });
      transaction.create(migrationRef, {
        schemaVersion: MIGRATION_SCHEMA_VERSION,
        uid,
        status: "reconciling",
        bootstrapCompleted: true,
        evidenceCursor: null,
        evidenceEventCount: 0,
        legacyClaimedTitleCount: progress.legacyUnlockedTitleIds.length,
        legacyMetricFloors: progress.legacyMetricFloors,
        startedAt: timestamp,
        updatedAt: timestamp,
      });
      return { outcome: "initialized", evidenceCursor: null, evidenceEventCount: 0 };
    });
  }

  async saveUserProgress({ uid, evidenceCursor, evidenceEventCount, now }) {
    await this.database().collection("achievementMigrations").doc(uid).set({
      status: "reconciling",
      evidenceCursor,
      evidenceEventCount,
      updatedAt: dateFrom(now, "Migration timestamp"),
    }, { merge: true });
  }

  async completeUser({ uid, evidenceEventCount, now }) {
    const database = this.database();
    const timestamp = dateFrom(now, "Migration timestamp");
    const migrationRef = database.collection("achievementMigrations").doc(uid);
    const userRef = database.collection("users").doc(uid);
    await database.runTransaction(async (transaction) => {
      const [migrationSnapshot, userSnapshot] = typeof transaction.getAll === "function"
        ? await transaction.getAll(migrationRef, userRef)
        : await Promise.all([
            transaction.get(migrationRef),
            transaction.get(userRef),
          ]);
      if (!migrationSnapshot.exists) {
        throw new AchievementMigrationError("User migration state disappeared.");
      }
      transaction.set(migrationRef, {
        status: userSnapshot.exists ? "verified" : "skipped:missing-user",
        evidenceCursor: null,
        evidenceEventCount,
        completedAt: timestamp,
        updatedAt: timestamp,
      }, { merge: true });
      if (userSnapshot.exists) {
        transaction.set(userRef, {
          achievementVerificationStatus: "verified",
          achievementsUpdatedAt: timestamp,
        }, { merge: true });
      }
    });
  }

  async failUser({ uid, now }) {
    await this.database().collection("achievementMigrations").doc(uid).set({
      status: "failed",
      failureCode: "canonical-reconciliation-failed",
      updatedAt: dateFrom(now, "Migration timestamp"),
    }, { merge: true });
  }
}

function createAchievementMigrationService({
  store = new FirestoreAchievementMigrationStore(),
  evidenceSource = createBoundedCanonicalEvidenceSource(),
  runtimeProvider = getDefaultAchievementRuntime,
  clock = () => new Date(),
  usersPerRun = DEFAULT_USERS_PER_RUN,
  eventsPerPage = DEFAULT_EVENTS_PER_PAGE,
} = {}) {
  if (!store || ![
    "beginUser",
    "completeUser",
    "failUser",
    "loadState",
    "nextUser",
    "saveState",
    "saveUserProgress",
    "user",
  ].every((name) => typeof store[name] === "function") ||
      !evidenceSource || typeof evidenceSource.readPage !== "function" ||
      typeof runtimeProvider !== "function" || typeof clock !== "function") {
    throw new TypeError("A migration store, evidence source, runtime and clock are required.");
  }
  requireBound(usersPerRun, 1, MAX_USERS_PER_RUN, "Users per run");
  requireBound(eventsPerPage, 1, MAX_EVENTS_PER_PAGE, "Events per page");

  async function runPage() {
    const startedAt = dateFrom(clock(), "Migration clock");
    const state = await store.loadState();
    if (state.complete) {
      return { outcome: "complete", usersCompleted: 0, eventsProcessed: 0 };
    }
    let usersCompleted = 0;
    let eventsProcessed = 0;
    while (usersCompleted < usersPerRun && !state.complete) {
      const record = state.currentUid
        ? await store.user(state.currentUid)
        : await store.nextUser(state.afterUid);
      if (!record) {
        if (state.currentUid) {
          state.afterUid = state.currentUid;
          state.currentUid = null;
          usersCompleted += 1;
          await store.saveState(state, clock());
          continue;
        }
        state.currentUid = null;
        state.complete = true;
        await store.saveState(state, clock());
        break;
      }
      const { uid, user } = record;
      state.currentUid = uid;
      await store.saveState(state, clock());
      try {
        const started = await store.beginUser({ uid, user, now: clock() });
        if (started.outcome === "missing") {
          state.afterUid = uid;
          state.currentUid = null;
          usersCompleted += 1;
          await store.saveState(state, clock());
          continue;
        }
        const page = await evidenceSource.readPage({
          uid,
          cursor: started.evidenceCursor ?? null,
          limit: eventsPerPage,
        });
        if (!page || !Array.isArray(page.events) ||
            page.events.length > eventsPerPage || typeof page.done !== "boolean") {
          throw new AchievementMigrationError("Evidence page is malformed.");
        }
        const runtime = runtimeProvider();
        if (!runtime || typeof runtime.processSourceEvent !== "function") {
          throw new AchievementMigrationError("Achievement runtime is unavailable.");
        }
        for (const event of page.events) {
          // Replay safety belongs to the event ledger; a crash before saving
          // this cursor can only replay, never double-increment.
          await runtime.processSourceEvent(event, { includeActiveDay: true });
          eventsProcessed += 1;
        }
        const evidenceEventCount = (started.evidenceEventCount ?? 0) +
          page.events.length;
        if (page.done) {
          await store.completeUser({ uid, evidenceEventCount, now: clock() });
          state.afterUid = uid;
          state.currentUid = null;
          usersCompleted += 1;
          await store.saveState(state, clock());
        } else {
          await store.saveUserProgress({
            uid,
            evidenceCursor: page.cursor ?? null,
            evidenceEventCount,
            now: clock(),
          });
          await store.saveState(state, clock());
          break;
        }
      } catch (error) {
        try {
          await store.failUser({ uid, now: clock() });
        } catch (_) {
          // Preserve the canonical error; the scheduler retry can repair the
          // diagnostic state, while swallowing it would skip the user.
        }
        throw error;
      }
    }
    return {
      outcome: state.complete ? "complete" : "progressed",
      usersCompleted,
      eventsProcessed,
      startedAt,
      cursor: {
        afterUid: state.afterUid ?? null,
        currentUid: state.currentUid ?? null,
      },
    };
  }

  return Object.freeze({ runPage });
}

let defaultMigrationService = null;

function getDefaultAchievementMigrationService() {
  if (!defaultMigrationService) {
    // No provider means no historical client claim is promoted. Canonical
    // source-specific providers can be registered during cutover; meanwhile
    // live triggers rebuild verified progress from server events only.
    defaultMigrationService = createAchievementMigrationService();
  }
  return defaultMigrationService;
}

const reconcileAchievementsV1 = onSchedule({
  schedule: "every 15 minutes",
  region: REGION,
  timeZone: "UTC",
  maxInstances: 1,
  timeoutSeconds: 300,
}, async () => getDefaultAchievementMigrationService().runPage());

module.exports = {
  AchievementMigrationError,
  DEFAULT_EVENTS_PER_PAGE,
  DEFAULT_USERS_PER_RUN,
  FirestoreAchievementMigrationStore,
  GLOBAL_STATE_PATH,
  MAX_EVENTS_PER_PAGE,
  MAX_USERS_PER_RUN,
  MIGRATION_SCHEMA_VERSION,
  REGION,
  createAchievementMigrationService,
  createBoundedCanonicalEvidenceSource,
  getDefaultAchievementMigrationService,
  normalizeEvidenceCursor,
  reconcileAchievementsV1,
};
