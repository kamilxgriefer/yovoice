function buildPushMessage({
  tokens,
  type,
  targetId,
  actorId,
  notificationId,
  title,
}) {
  return {
    tokens,
    notification: { title, body: "Tap to open YO Voice" },
    data: {
      type: String(type),
      targetId: targetId ? String(targetId) : "",
      actorId: actorId ? String(actorId) : "",
      notificationId,
    },
    android: {
      priority: "high",
      notification: {
        channelId: "yovoice_default",
        sound: "default",
        defaultVibrateTimings: true,
      },
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          interruptionLevel: "active",
        },
      },
    },
    webpush: {
      notification: {
        icon: "/icons/Icon-192.png",
        badge: "/icons/Icon-192.png",
        requireInteraction: false,
      },
    },
  };
}

module.exports = { buildPushMessage };
