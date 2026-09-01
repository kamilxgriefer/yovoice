const { getStorage } = require("firebase-admin/storage");
const { FieldPath, Timestamp } = require("firebase-admin/firestore");
const { onCall } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const {
  requireBoolean,
  requireExactInput,
  requireSafeInteger,
} = require("../integrity/guards");
const { createBucketStorageAdapter } = require("../moments/integrity");
const { requireProtectedOwner } = require("../utils/auth");
const { db } = require("../utils/firestore");
const { createProfileMediaService } = require("./media");
const { createProfileMediaCleanupService } = require("./media_cleanup");
const {
  createProfileIdentitySnapshotMigration,
} = require("./identity_snapshot_migration");
const { createProfileMediaMigrationService } = require("./media_migration");

const REGION = "europe-west1";

function createProfileMediaRuntime({
  database = db,
  timestamp = Timestamp,
  fieldPath = FieldPath,
  storage = null,
  clock = () => Date.now(),
} = {}) {
  const objectStorage =
    storage ?? createBucketStorageAdapter(getStorage().bucket());
  const media = createProfileMediaService({
    db: database,
    Timestamp: timestamp,
    storage: objectStorage,
    clock,
  });
  const migration = createProfileMediaMigrationService({
    db: database,
    Timestamp: timestamp,
    FieldPath: fieldPath,
    storage: objectStorage,
    clock,
  });
  return Object.freeze({
    media,
    migration,
    cleanup: createProfileMediaCleanupService({
      db: database,
      storage: objectStorage,
      migration,
      clock,
    }),
    identitySnapshots: createProfileIdentitySnapshotMigration({ db: database }),
  });
}

function createProfileMediaFunctions({ runtime = null } = {}) {
  const resolved = runtime ?? createProfileMediaRuntime();
  const userOptions = {
    region: REGION,
    memory: "256MiB",
    timeoutSeconds: 60,
    maxInstances: 50,
    minInstances: 0,
    enforceAppCheck: false,
  };
  const migrationOptions = {
    region: REGION,
    memory: "1GiB",
    timeoutSeconds: 540,
    maxInstances: 1,
    minInstances: 0,
    enforceAppCheck: false,
  };

  return Object.freeze({
    reserveProfileMediaUpload: onCall(
      userOptions,
      resolved.media.reserveProfileMediaUpload,
    ),
    finalizeProfileMediaUpload: onCall(
      userOptions,
      resolved.media.finalizeProfileMediaUpload,
    ),
    getProfileMediaAccess: onCall(
      userOptions,
      resolved.media.getProfileMediaAccess,
    ),
    scanProfileMediaMigration: onCall(migrationOptions, async (request) => {
      await requireProtectedOwner(request);
      const data = requireExactInput(request.data, ["cursor", "limit"]);
      return resolved.migration.scanProfileMediaMigration({
        cursor:
          data.cursor === undefined || data.cursor === null
            ? null
            : data.cursor,
        limit:
          data.limit === undefined
            ? 25
            : requireSafeInteger(data.limit, "limit", { min: 1, max: 100 }),
      });
    }),
    migrateProfileMediaRecord: onCall(migrationOptions, async (request) => {
      const data = requireExactInput(
        request.data,
        ["dryRun", "userId"],
        ["dryRun", "userId"],
      );
      const dryRun = requireBoolean(data.dryRun, "dryRun");
      await requireProtectedOwner(request, { privileged: !dryRun });
      return resolved.migration.migrateProfileMedia({
        userId: data.userId,
        dryRun,
      });
    }),
    inventoryProfileMediaObjects: onCall(migrationOptions, async (request) => {
      const data = requireExactInput(
        request.data,
        ["cursor", "limit", "revokeTokens"],
        ["revokeTokens"],
      );
      const revokeTokens = requireBoolean(data.revokeTokens, "revokeTokens");
      await requireProtectedOwner(request, { privileged: revokeTokens });
      return resolved.migration.inventoryProfileMediaObjects({
        cursor:
          data.cursor === undefined || data.cursor === null
            ? null
            : data.cursor,
        limit:
          data.limit === undefined
            ? 100
            : requireSafeInteger(data.limit, "limit", { min: 1, max: 200 }),
        revokeTokens,
      });
    }),
    cleanupProfileMediaUploads: onSchedule(
      {
        region: REGION,
        schedule: "every 60 minutes",
        timeZone: "UTC",
        memory: "512MiB",
        timeoutSeconds: 540,
        maxInstances: 1,
      },
      async () => {
        // Persist the opaque provider cursor so a large bucket cannot starve
        // orphan objects beyond the first page. Completion wraps to page one.
        await resolved.cleanup.scheduledSweep({ limit: 200 });
      },
    ),
    scrubProfileIdentitySnapshots: onCall(migrationOptions, async (request) => {
      const data = requireExactInput(
        request.data,
        ["cursor", "dryRun", "limit", "target"],
        ["dryRun", "target"],
      );
      const dryRun = requireBoolean(data.dryRun, "dryRun");
      await requireProtectedOwner(request, { privileged: !dryRun });
      return resolved.identitySnapshots.scrub({
        target: data.target,
        cursor:
          data.cursor === undefined || data.cursor === null
            ? null
            : data.cursor,
        limit:
          data.limit === undefined
            ? 100
            : requireSafeInteger(data.limit, "limit", { min: 1, max: 200 }),
        dryRun,
      });
    }),
  });
}

module.exports = {
  REGION,
  createProfileMediaFunctions,
  createProfileMediaRuntime,
};
