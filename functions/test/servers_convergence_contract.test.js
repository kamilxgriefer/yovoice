const assert = require("node:assert/strict");
const { test } = require("node:test");
const { canonicalLiveKitRoomName } = require("../servers/contract");
const { convergenceState } = require("../servers/convergence_lifecycle");
const { immutableJobFingerprint, validateConvergenceJob } = require("../servers/convergence_runtime");

const operationId = "bridge-operation";
const target = { serverId: "server", channelId: "channel", roomId: "anchor", sessionId: "generation",
  livekitRoomName: canonicalLiveKitRoomName("server", "channel", "generation"), mode: "recipient", userId: "person:opaque" };
const job = () => ({ schemaVersion: 1, operationId, kind: "memberLeft", serverId: "server",
  userId: target.userId, membershipRevision: 2, status: "pending", ...convergenceState([{ ...target }]) });

test("old convergence jobs never infer empty RTC obligations from missing version or targets", () => {
  for (const field of ["convergenceVersion", "rtcTargets"]) {
    const value = job(); delete value[field];
    assert.throws(() => validateConvergenceJob(value, operationId));
  }
  const value = job(); value.convergenceVersion = 2;
  assert.throws(() => validateConvergenceJob(value, operationId));
});

test("bridge validates canonical scope, mode and opaque recipient identity", () => {
  assert.equal(validateConvergenceJob(job(), operationId).userId, "person:opaque");
  for (const patch of [{ serverId: "other" }, { livekitRoomName: "forged" },
    { userId: "foreign" }, { mode: "sessionEnd", endOperationId: "foreign-end" }]) {
    const value = job(); value.rtcTargets[0] = { ...target, ...patch };
    assert.throws(() => validateConvergenceJob(value, operationId));
  }
  const duplicate = job(); duplicate.rtcTargets.push({ ...target });
  assert.throws(() => validateConvergenceJob(duplicate, operationId));
});

test("bridge rejects completed claims with outstanding grants, RTC or content", () => {
  const value = job(); value.status = "completed";
  assert.throws(() => validateConvergenceJob(value, operationId));
  const deleted = { schemaVersion: 1, operationId, kind: "channelDelete", serverId: "server", channelId: "channel",
    status: "completed", ...convergenceState([], { contentCleanupPending: true }) };
  assert.throws(() => validateConvergenceJob(deleted, operationId));
});

test("immutable bridge fencing includes all targets and authority provenance but not progress", () => {
  const value = job(); const hash = immutableJobFingerprint(value);
  assert.equal(immutableJobFingerprint({ ...value, bridgeLeaseId: "different-lease", rtcStatus: "recoveryRequired" }), hash);
  assert.notEqual(immutableJobFingerprint({ ...value, membershipRevision: 3 }), hash);
  assert.notEqual(immutableJobFingerprint({ ...value, rtcTargets: [] }), hash);
});
