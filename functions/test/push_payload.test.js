const assert = require("node:assert/strict");
const { test } = require("node:test");

const { buildPushMessage } = require("../notifications/push_payload");

test("push payload requests an audible visible notification on every platform", () => {
  const message = buildPushMessage({
    tokens: ["token-a"],
    type: "directMessage",
    targetId: "conversation-1",
    actorId: "user-2",
    notificationId: "notification-3",
    title: "Alex sent you a message",
  });

  assert.deepEqual(message.tokens, ["token-a"]);
  assert.deepEqual(message.notification, {
    title: "Alex sent you a message",
    body: "Tap to open YO Voice",
  });
  assert.equal(message.android.priority, "high");
  assert.equal(message.android.notification.channelId, "yovoice_activity_v2");
  assert.equal(message.android.notification.sound, "yovoice_notification");
  assert.equal(message.android.notification.defaultVibrateTimings, true);
  assert.equal(message.apns.payload.aps.sound, "yovoice_notification.wav");
  assert.equal(message.apns.payload.aps.interruptionLevel, "active");
  assert.equal(message.webpush.notification.icon, "/icons/Icon-192.png");
  assert.equal(message.webpush.notification.requireInteraction, false);
});

test("push routing data is always string-valued", () => {
  const message = buildPushMessage({
    tokens: ["token-a"],
    type: "system",
    targetId: null,
    actorId: undefined,
    notificationId: "notification-4",
    title: "YO Voice",
  });

  assert.deepEqual(message.data, {
    type: "system",
    targetId: "",
    actorId: "",
    notificationId: "notification-4",
  });
});
