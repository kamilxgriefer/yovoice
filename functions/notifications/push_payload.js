function buildPushMessage({
  tokens,
  type,
  targetId,
  actorId,
  notificationId,
  title,
  collapseId,
}) {
  if (typeof collapseId !== "string" || collapseId.length === 0 ||
      collapseId.length > 64) {
    throw new TypeError("A valid platform collapse identifier is required.");
  }
  const isCall = type === "directCall";
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
      collapseKey: collapseId,
      notification: {
        tag: collapseId,
        channelId: isCall ? "yovoice_calls_v1" : "yovoice_activity_v3",
        sound: "yovoice_notification",
        defaultVibrateTimings: true,
        ...(isCall ? { visibility: "public" } : {}),
      },
    },
    apns: {
      headers: { "apns-collapse-id": collapseId },
      payload: {
        aps: {
          sound: "yovoice_notification.wav",
          interruptionLevel: isCall ? "time-sensitive" : "active",
          ...(isCall ? { category: "YOVOICE_DIRECT_CALL" } : {}),
        },
      },
    },
    webpush: {
      notification: {
        tag: collapseId,
        icon: "/icons/Icon-192.png",
        badge: "/icons/Icon-192.png",
        requireInteraction: isCall,
      },
    },
  };
}

module.exports = { buildPushMessage };
