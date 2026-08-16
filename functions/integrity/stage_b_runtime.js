const {
  FieldPath,
  getFirestore,
  Timestamp,
} = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

const {
  createDirectMessagingService,
} = require("../messaging/direct_integrity");
const {
  createDirectMigrationService,
} = require("../messaging/direct_migration");
const {
  createBucketStorageAdapter,
  createMomentIntegrityService,
} = require("../moments/integrity");
const {
  createMomentMigrationService,
} = require("../moments/migration");

/**
 * Creates one dependency graph for the Stage B bindings.
 *
 * Nothing is initialized at module import time. `functions/index.js` can call
 * this after `initializeApp()`, while emulator/unit tests inject isolated
 * Firestore and Storage implementations without touching production globals.
 */
function createStageBIntegrityRuntime({
  db = null,
  bucket = null,
  storage = null,
  FieldPathImpl = FieldPath,
  TimestampImpl = Timestamp,
  clock = () => Date.now(),
  directOptions = {},
  momentOptions = {},
  directMigrationOptions = {},
  momentMigrationOptions = {},
} = {}) {
  const database = db ?? getFirestore();
  const objectStorage = storage ?? createBucketStorageAdapter(
    bucket ?? getStorage().bucket(),
  );

  const direct = createDirectMessagingService({
    db: database,
    Timestamp: TimestampImpl,
    clock,
    ...directOptions,
  });
  const moments = createMomentIntegrityService({
    db: database,
    FieldPath: FieldPathImpl,
    Timestamp: TimestampImpl,
    storage: objectStorage,
    clock,
    ...momentOptions,
  });
  const directMigration = createDirectMigrationService({
    db: database,
    FieldPath: FieldPathImpl,
    Timestamp: TimestampImpl,
    clock,
    ...directMigrationOptions,
  });
  const momentMigration = createMomentMigrationService({
    db: database,
    FieldPath: FieldPathImpl,
    Timestamp: TimestampImpl,
    storage: objectStorage,
    clock,
    ...momentMigrationOptions,
  });

  return Object.freeze({
    clock,
    db: database,
    direct,
    directMigration,
    FieldPath: FieldPathImpl,
    moments,
    momentMigration,
    storage: objectStorage,
    Timestamp: TimestampImpl,
  });
}

module.exports = { createStageBIntegrityRuntime };
