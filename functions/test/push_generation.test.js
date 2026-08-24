const assert = require("node:assert/strict");
const test = require("node:test");

const {
  isCurrentNotificationGeneration,
} = require("../notifications/push_generation");

function time(value) {
  return { isEqual: (other) => other?.value === value, value };
}

test("push generation accepts only the current Firestore create", () => {
  const created = { createTime: time(1) };
  assert.equal(
    isCurrentNotificationGeneration(created, {
      exists: true,
      createTime: time(1),
    }),
    true,
  );
  assert.equal(
    isCurrentNotificationGeneration(created, { exists: false }),
    false,
    "a cancelled request must not push",
  );
  assert.equal(
    isCurrentNotificationGeneration(created, {
      exists: true,
      createTime: time(2),
    }),
    false,
    "a recreated deterministic id is a different request lifecycle",
  );
});
