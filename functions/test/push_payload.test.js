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
    collapseId: "generation-collapse-1",
  });

  assert.deepEqual(message.tokens, ["token-a"]);
  assert.deepEqual(message.notification, {
    title: "Alex sent you a message",
    body: "Tap to open YO Voice",
  });
  assert.equal(message.android.priority, "high");
  assert.equal(message.android.collapseKey, "generation-collapse-1");
  assert.equal(message.android.notification.tag, "generation-collapse-1");
  assert.equal(message.android.notification.channelId, "yovoice_activity_v3");
  assert.equal(message.android.notification.sound, "yovoice_notification");
  assert.equal(message.android.notification.defaultVibrateTimings, true);
  assert.equal(message.apns.payload.aps.sound, "yovoice_notification.wav");
  assert.equal(message.apns.payload.aps.interruptionLevel, "active");
  assert.equal(
    message.apns.headers["apns-collapse-id"],
    "generation-collapse-1",
  );
  assert.equal(message.webpush.notification.icon, "/icons/Icon-192.png");
  assert.equal(message.webpush.notification.tag, "generation-collapse-1");
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
    collapseId: "generation-collapse-2",
  });

  assert.deepEqual(message.data, {
    type: "system",
    targetId: "",
    actorId: "",
    notificationId: "notification-4",
  });
});

test("direct-call notification hides caller details from APNs and Web Push", () => {
  const message = buildPushMessage({
    tokens: ["token-a"],
    type: "directCall",
    targetId: "call-1",
    actorId: "caller-1",
    notificationId: "notification-call-1",
    title: "Alex is video calling you",
    collapseId: "direct-call-1",
  });

  assert.deepEqual(message.notification, {
    title: "Incoming YO Voice call",
    body: "Open YO Voice to answer.",
  });
  assert.equal(message.android.priority, "high");
  assert.equal(message.android.notification.visibility, "private");
  assert.equal(message.android.notification.channelId, "yovoice_calls_v1");
  assert.equal(message.android.notification.title, "Alex is video calling you");
  assert.equal(message.android.notification.body, "Tap to open YO Voice");
  assert.equal(message.apns.payload.aps.interruptionLevel, "time-sensitive");
  assert.deepEqual(message.apns.payload.aps.alert, {
    title: "Incoming YO Voice call",
    body: "Open YO Voice to answer.",
  });
  assert.equal(message.webpush.notification.title, "Incoming YO Voice call");
  assert.equal(
    message.webpush.notification.body,
    "Open YO Voice to answer.",
  );
  assert.equal(message.webpush.notification.requireInteraction, true);
  assert.equal(JSON.stringify(message.apns).includes("Alex"), false);
  assert.equal(JSON.stringify(message.apns).includes("video"), false);
  assert.equal(JSON.stringify(message.webpush).includes("Alex"), false);
  assert.equal(JSON.stringify(message.webpush).includes("video"), false);
});

test("missed-call notification also hides caller details outside Android", () => {
  const message = buildPushMessage({
    tokens: ["token-a"],
    type: "missedCall",
    targetId: "call-2",
    actorId: "caller-1",
    notificationId: "notification-call-2",
    title: "Missed video call from Alex",
    collapseId: "direct-call-2",
  });

  assert.deepEqual(message.notification, {
    title: "Missed YO Voice call",
    body: "Open YO Voice to view the call.",
  });
  assert.equal(message.android.notification.visibility, "private");
  assert.equal(message.android.notification.title, "Missed video call from Alex");
  assert.equal(message.android.notification.channelId, "yovoice_activity_v3");
  assert.deepEqual(message.apns.payload.aps.alert, {
    title: "Missed YO Voice call",
    body: "Open YO Voice to view the call.",
  });
  assert.equal(message.apns.payload.aps.interruptionLevel, "active");
  assert.equal(message.webpush.notification.requireInteraction, false);
  assert.equal(JSON.stringify(message.apns).includes("Alex"), false);
  assert.equal(JSON.stringify(message.webpush).includes("Alex"), false);
});
