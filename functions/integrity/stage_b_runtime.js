const {
  FieldValue,
  FieldPath,
  getFirestore,
  Timestamp,
} = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

const {
  createDirectMessagingService,
} = require("../messaging/direct_integrity");
const {
  createCommunityMessagingService,
} = require("../messaging/community_integrity");
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
const { createRoomCoverService } = require("../rooms/covers");
const { createRoomCreationService } = require("../rooms/creation");
const {
  createRoomCoverMigrationService,
} = require("../rooms/cover_migration");
const { createTrustedGcsMediaProbe } = require("../reels/probe");

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
  communityOptions = {},
  momentOptions = {},
  directMigrationOptions = {},
  momentMigrationOptions = {},
  roomCoverOptions = {},
  roomCreationOptions = {},
  roomCoverMigrationOptions = {},
} = {}) {
  const database = db ?? getFirestore();
  const objectBucket = bucket ?? (storage ? null : getStorage().bucket());
  const objectStorage = storage ?? createBucketStorageAdapter(objectBucket);
  const {
    mediaProbe: configuredDirectMediaProbe,
    ...remainingDirectOptions
  } = directOptions;
  const directMediaProbe = configuredDirectMediaProbe ??
    (objectBucket ? createTrustedGcsMediaProbe(objectBucket) : null);

  const direct = createDirectMessagingService({
    db: database,
    Timestamp: TimestampImpl,
    storage: objectStorage,
    mediaProbe: directMediaProbe,
    clock,
    ...remainingDirectOptions,
  });
  const community = createCommunityMessagingService({
    db: database,
    Timestamp: TimestampImpl,
    clock,
    ...communityOptions,
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
  const roomCovers = createRoomCoverService({
    db: database,
    Timestamp: TimestampImpl,
    storage: objectStorage,
    clock,
    ...roomCoverOptions,
  });
  const roomCreation = createRoomCreationService({
    db: database,
    FieldValue,
    Timestamp: TimestampImpl,
    clock,
    ...roomCreationOptions,
  });
  const roomCoverMigration = createRoomCoverMigrationService({
    db: database,
    FieldPath: FieldPathImpl,
    Timestamp: TimestampImpl,
    storage: objectStorage,
    clock,
    ...roomCoverMigrationOptions,
  });

  return Object.freeze({
    clock,
    community,
    db: database,
    direct,
    directMigration,
    FieldPath: FieldPathImpl,
    moments,
    momentMigration,
    roomCovers,
    roomCreation,
    roomCoverMigration,
    storage: objectStorage,
    Timestamp: TimestampImpl,
  });
}

module.exports = { createStageBIntegrityRuntime };
