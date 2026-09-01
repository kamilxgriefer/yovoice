const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  USER_CALLABLE_METHODS,
  createUserCallableHandlers,
} = require("../integrity/stage_b_handlers");
const {
  REGION,
  createStageBFunctions,
} = require("../integrity/stage_b_functions");

function fakeRuntime(calls = []) {
  const service = (serviceName, methodName) => async (request) => {
    calls.push({ serviceName, methodName, request });
    return { serviceName, methodName, uid: request.auth.uid };
  };
  const direct = {};
  const community = {};
  direct.expireAbandonedAttachmentReservations = async () => ({ expired: [] });
  const moments = {
    processCleanupOutbox: async () => ({ completed: true }),
    expireAbandonedMomentDrafts: async () => ({ expired: [] }),
    expireAbandonedVoiceCommentDrafts: async () => ({ expired: [] }),
  };
  const roomCovers = {
    expireRoomCoverUploadReservations: async () => ({ expired: [] }),
  };
  const roomCreation = {};
  for (const [, [serviceName, methodName]] of Object.entries(
    USER_CALLABLE_METHODS,
  )) {
    ({ community, direct, moments, roomCovers, roomCreation })[serviceName][
      methodName
    ] = service(serviceName, methodName);
  }
  return {
    clock: () => 1_900_000_000_000,
    community,
    db: {},
    direct,
    directMigration: {
      migrateDirectConversation: async () => ({}),
      scanDirectConversationMigration: async () => ({}),
    },
    FieldPath: { documentId: () => ({}) },
    moments,
    momentMigration: {
      migrateMoment: async () => ({}),
      scanMomentMigration: async () => ({}),
    },
    roomCovers,
    roomCreation,
    roomCoverMigration: {
      migrateRoomCover: async () => ({}),
      scanRoomCoverMigration: async () => ({}),
      scanRoomCoverObjectInventory: async () => ({}),
    },
    storage: { getMetadata: async () => ({}) },
    Timestamp: { fromMillis: (value) => ({ toMillis: () => value }) },
  };
}

function fakeRegistrars(registrations) {
  const register = (kind) => (options, handler) => {
    const registered = { kind, options: { ...options }, handler };
    registrations.push(registered);
    return registered;
  };
  return {
    onCall: register("callable"),
    onSchedule: register("schedule"),
    onDocumentCreated: register("created"),
  };
}

test("user callable bindings preserve Auth uid and discard transport identity", async () => {
  const calls = [];
  const handlers = createUserCallableHandlers(fakeRuntime(calls));
  const raw = {
    auth: {
      uid: "opaque user-Ż",
      token: { email_verified: true, role: "user" },
    },
    app: { appId: "untrusted-transport-field" },
    data: { requestId: "binding-0001", senderId: "forged" },
    instanceIdToken: "discard-me",
    rawRequest: { headers: { "x-forged-uid": "attacker" } },
  };
  const result = await handlers.sendDirectMessage(raw);
  assert.equal(result.uid, "opaque user-Ż");
  assert.deepEqual(calls[0].request, {
    auth: {
      uid: "opaque user-Ż",
      token: { email_verified: true, role: "user" },
    },
    data: raw.data,
  });
  assert.equal("app" in calls[0].request, false);
  assert.equal("rawRequest" in calls[0].request, false);

  await assert.rejects(
    handlers.sendDirectMessage({ data: raw.data }),
    (error) => error.code === "unauthenticated",
  );
  await assert.rejects(
    handlers.sendDirectMessage({
      auth: { uid: "bad/uid", token: { email_verified: true } },
      data: raw.data,
    }),
    (error) => error.code === "unauthenticated",
  );
  assert.equal(calls.length, 1);
});

test("Stage B export map registers every callable, schedule and trigger", () => {
  const registrations = [];
  const functions = createStageBFunctions({
    runtime: fakeRuntime(),
    registrars: fakeRegistrars(registrations),
    authorizeMigration: async (request) => ({ uid: request.auth.uid }),
    log: { info() {}, error() {} },
  });

  const callableNames = [
    ...Object.keys(USER_CALLABLE_METHODS),
    "scanDirectIntegrityMigration",
    "migrateDirectIntegrityConversation",
    "scanMomentIntegrityMigration",
    "migrateIntegrityMoment",
    "scanRoomCoverIntegrityMigration",
    "migrateIntegrityRoomCover",
    "scanRoomCoverObjectInventory",
  ];
  const scheduleNames = [
    "processPendingContentCleanupSchedule",
    "expireAbandonedMomentDraftsSchedule",
    "expireAbandonedVoiceCommentDraftsSchedule",
    "expireAbandonedDirectMessageAttachmentsSchedule",
    "expireRoomCoverUploadReservationsSchedule",
  ];
  const triggerNames = ["onContentCleanupOutboxCreated"];
  assert.deepEqual(
    Object.keys(functions).sort(),
    [...callableNames, ...scheduleNames, ...triggerNames].sort(),
  );
  assert.equal(
    registrations.filter((item) => item.kind === "callable").length,
    callableNames.length,
  );
  assert.equal(
    registrations.filter((item) => item.kind === "schedule").length,
    5,
  );
  assert.equal(
    registrations.filter((item) => item.kind === "created").length,
    1,
  );

  for (const name of callableNames) {
    assert.equal(functions[name].options.region, REGION);
    assert.equal(functions[name].options.enforceAppCheck, false);
  }
  assert.equal(functions.migrateIntegrityMoment.options.maxInstances, 1);
  assert.equal(
    functions.processPendingContentCleanupSchedule.options.maxInstances,
    1,
  );
  assert.equal(
    functions.onContentCleanupOutboxCreated.options.document,
    "contentCleanupOutbox/{outboxId}",
  );
  assert.equal(
    Object.keys(functions).some((name) => name.includes("Achievement")),
    false,
  );
});

test("App Check can be enabled at registration without changing handlers", () => {
  const functions = createStageBFunctions({
    runtime: fakeRuntime(),
    registrars: fakeRegistrars([]),
    authorizeMigration: async (request) => ({ uid: request.auth.uid }),
    enforceUserAppCheck: true,
    enforceMigrationAppCheck: true,
  });
  assert.equal(functions.sendDirectMessage.options.enforceAppCheck, true);
  assert.equal(functions.sendDirectMessage.options.consumeAppCheckToken, true);
  assert.equal(
    functions.scanDirectIntegrityMigration.options.enforceAppCheck,
    true,
  );
  assert.equal(
    functions.scanDirectIntegrityMigration.options.consumeAppCheckToken,
    true,
  );
});
