const assert = require("node:assert/strict");
const { test } = require("node:test");

process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();

const {
  claimPushDelivery,
  notificationSourceIsCurrent,
} = require("../notifications/push");

class FakeTimestamp {
  constructor(seconds, nanoseconds) {
    this.seconds = seconds;
    this.nanoseconds = nanoseconds;
  }

  isEqual(other) {
    return this.seconds === other?.seconds &&
      this.nanoseconds === other?.nanoseconds;
  }

  toMillis() {
    return this.seconds * 1000 + Math.floor(this.nanoseconds / 1e6);
  }
}

test("social source conflict retries the claim into terminal skipped", async () => {
  const generation = new FakeTimestamp(1_787_900_000, 123_000_000);
  const notificationPath =
    "users/recipient/notifications/friendRequest_actor_generation";
  const sourcePath = "users/recipient/friendRequests/actor";
  const notificationReference = { path: notificationPath };
  const state = {
    sourceExists: true,
    data: {
      type: "friendRequest",
      actorId: "actor",
      actorName: "Ada",
    },
  };
  let attempts = 0;
  const firestore = {
    doc: (path) => ({ path }),
    runTransaction: async (handler) => {
      while (true) {
        attempts++;
        const pending = { ...state.data };
        const transaction = {
          get: async (reference) => {
            if (reference.path === notificationPath) {
              return {
                exists: true,
                createTime: generation,
                data: () => ({ ...state.data }),
              };
            }
            assert.equal(reference.path, sourcePath);
            return {
              exists: state.sourceExists,
              data: () => state.sourceExists
                ? { notificationId: "friendRequest_actor_generation" }
                : undefined,
            };
          },
          update: (reference, patch) => {
            assert.equal(reference.path, notificationPath);
            Object.assign(pending, patch);
          },
        };
        const result = await handler(transaction);
        if (attempts === 1) {
          // Models Firestore discarding the first transaction after the source
          // it read changed concurrently, then invoking the callback again.
          assert.equal(result.state, "claimed");
          state.sourceExists = false;
          continue;
        }
        state.data = pending;
        return result;
      }
    },
  };
  const notificationSnapshot = {
    ref: notificationReference,
    createTime: generation,
  };

  const result = await claimPushDelivery({
    eventId: "redelivered-envelope",
    userId: "recipient",
    notificationId: "friendRequest_actor_generation",
    notificationSnapshot,
  }, {
    firestore,
    validate: (transaction, notification) => notificationSourceIsCurrent({
      recipientId: "recipient",
      notificationId: "friendRequest_actor_generation",
      notification,
      firestore,
      reader: transaction,
    }),
  });

  assert.equal(attempts, 2);
  assert.deepEqual(result, { state: "terminal", reason: "invalid-source" });
  assert.equal(state.data.pushDeliveryStatus, "skipped");
  assert.equal(state.data.pushSkipReason, "invalid-source");
  assert.equal(state.data.pushClaimEventId, undefined);
});
