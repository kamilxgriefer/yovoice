const { logger } = require("firebase-functions/v2");
const { onCall } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const {
  onDocumentCreated,
} = require("firebase-functions/v2/firestore");

const { createMigrationControl } = require("./migration_control");
const {
  createMaintenanceHandlers,
  createUserCallableHandlers,
} = require("./stage_b_handlers");
const { createStageBIntegrityRuntime } = require("./stage_b_runtime");

const REGION = "europe-west1";

function callableOptions({ enforceAppCheck, privileged = false }) {
  return {
    region: REGION,
    memory: privileged ? "1GiB" : "256MiB",
    timeoutSeconds: privileged ? 540 : 60,
    maxInstances: privileged ? 1 : 50,
    minInstances: 0,
    enforceAppCheck: enforceAppCheck === true,
    consumeAppCheckToken: enforceAppCheck === true,
  };
}

function defaultRegistrars() {
  return { onCall, onSchedule, onDocumentCreated };
}

/**
 * Builds the complete Stage B Cloud Functions export map without mutating
 * `functions/index.js`. The integrator can later merge the returned properties
 * into `exports` in one reviewed cutover patch.
 */
function createStageBFunctions({
  runtime = null,
  registrars = defaultRegistrars(),
  authorizeMigration = null,
  log = logger,
  enforceUserAppCheck = false,
  enforceMigrationAppCheck = false,
  cleanupBatchSize = 12,
  expiryBatchSize = 100,
} = {}) {
  const resolvedRuntime = runtime ?? createStageBIntegrityRuntime();
  for (const name of [
    "onCall",
    "onSchedule",
    "onDocumentCreated",
  ]) {
    if (typeof registrars?.[name] !== "function") {
      throw new TypeError(`Missing Cloud Functions registrar: ${name}.`);
    }
  }

  const userHandlers = createUserCallableHandlers(resolvedRuntime);
  const migrationHandlers = createMigrationControl({
    db: resolvedRuntime.db,
    Timestamp: resolvedRuntime.Timestamp,
    directMigration: resolvedRuntime.directMigration,
    momentMigration: resolvedRuntime.momentMigration,
    roomCoverMigration: resolvedRuntime.roomCoverMigration,
    authorize: authorizeMigration,
    clock: resolvedRuntime.clock,
  });
  const maintenanceHandlers = createMaintenanceHandlers({
    db: resolvedRuntime.db,
    direct: resolvedRuntime.direct,
    FieldPath: resolvedRuntime.FieldPath,
    moments: resolvedRuntime.moments,
    roomCovers: resolvedRuntime.roomCovers,
    logger: log,
    cleanupBatchSize,
    expiryBatchSize,
  });
  const userOptions = callableOptions({ enforceAppCheck: enforceUserAppCheck });
  const privilegedOptions = callableOptions({
    enforceAppCheck: enforceMigrationAppCheck,
    privileged: true,
  });
  const exportsMap = {};
  for (const [name, handler] of Object.entries(userHandlers)) {
    exportsMap[name] = registrars.onCall(userOptions, handler);
  }
  exportsMap.scanDirectIntegrityMigration = registrars.onCall(
    privilegedOptions,
    migrationHandlers.scanDirectMigration,
  );
  exportsMap.migrateDirectIntegrityConversation = registrars.onCall(
    privilegedOptions,
    migrationHandlers.migrateDirectConversation,
  );
  exportsMap.scanMomentIntegrityMigration = registrars.onCall(
    privilegedOptions,
    migrationHandlers.scanMomentMigration,
  );
  exportsMap.migrateIntegrityMoment = registrars.onCall(
    privilegedOptions,
    migrationHandlers.migrateMoment,
  );
  exportsMap.scanRoomCoverIntegrityMigration = registrars.onCall(
    privilegedOptions,
    migrationHandlers.scanRoomCoverMigration,
  );
  exportsMap.migrateIntegrityRoomCover = registrars.onCall(
    privilegedOptions,
    migrationHandlers.migrateRoomCover,
  );
  exportsMap.scanRoomCoverObjectInventory = registrars.onCall(
    privilegedOptions,
    migrationHandlers.scanRoomCoverObjectInventory,
  );

  const scheduleBase = {
    region: REGION,
    timeZone: "Etc/UTC",
    memory: "512MiB",
    timeoutSeconds: 300,
    maxInstances: 1,
  };
  exportsMap.processPendingContentCleanupSchedule = registrars.onSchedule(
    { ...scheduleBase, schedule: "every 5 minutes" },
    maintenanceHandlers.processPendingContentCleanup,
  );
  exportsMap.expireAbandonedMomentDraftsSchedule = registrars.onSchedule(
    { ...scheduleBase, schedule: "every 10 minutes" },
    maintenanceHandlers.expireAbandonedMomentDrafts,
  );
  exportsMap.expireAbandonedVoiceCommentDraftsSchedule = registrars.onSchedule(
    { ...scheduleBase, schedule: "every 10 minutes" },
    maintenanceHandlers.expireAbandonedVoiceCommentDrafts,
  );
  exportsMap.expireAbandonedDirectMessageAttachmentsSchedule =
    registrars.onSchedule(
      { ...scheduleBase, schedule: "every 10 minutes" },
      maintenanceHandlers.expireAbandonedDirectMessageAttachments,
    );
  exportsMap.expireRoomCoverUploadReservationsSchedule =
    registrars.onSchedule(
      { ...scheduleBase, schedule: "every 10 minutes" },
      maintenanceHandlers.expireRoomCoverUploadReservations,
    );

  const eventBase = {
    region: REGION,
    memory: "256MiB",
    timeoutSeconds: 120,
    maxInstances: 50,
    retry: true,
  };
  exportsMap.onContentCleanupOutboxCreated = registrars.onDocumentCreated(
    { ...eventBase, document: "contentCleanupOutbox/{outboxId}" },
    maintenanceHandlers.onContentCleanupOutboxCreated,
  );

  return Object.freeze(exportsMap);
}

module.exports = {
  REGION,
  callableOptions,
  createStageBFunctions,
};
