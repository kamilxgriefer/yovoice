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
  const isIncomingCall = type === "directCall";
  const isPrivateCallNotice = isIncomingCall || type === "missedCall";
  const defaultBody = "Tap to open YO Voice";
  const publicTitle = isIncomingCall
    ? "Incoming YO Voice call"
    : type === "missedCall"
      ? "Missed YO Voice call"
      : title;
  const publicBody = isIncomingCall
    ? "Open YO Voice to answer."
    : type === "missedCall"
      ? "Open YO Voice to view the call."
      : defaultBody;
  return {
    tokens,
    // The common notification is the APNs/Web fallback and must not contain a
    // caller's display name or whether the call uses video. Android overrides
    // it below, where private visibility protects the lock-screen surface.
    notification: { title: publicTitle, body: publicBody },
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
        channelId: isIncomingCall
          ? "yovoice_calls_v1"
          : "yovoice_activity_v3",
        sound: "yovoice_notification",
        defaultVibrateTimings: true,
        // Keep caller details out of Android's public lock-screen surface.
        // The full incoming-call UI is shown only after the device applies
        // its own unlock/privacy policy.
        ...(isPrivateCallNotice ? {
          title,
          body: defaultBody,
          visibility: "private",
        } : {}),
      },
    },
    apns: {
      headers: { "apns-collapse-id": collapseId },
      payload: {
        aps: {
          sound: "yovoice_notification.wav",
          interruptionLevel: isIncomingCall ? "time-sensitive" : "active",
          ...(isIncomingCall ? { category: "YOVOICE_DIRECT_CALL" } : {}),
          ...(isPrivateCallNotice ? {
            alert: { title: publicTitle, body: publicBody },
          } : {}),
        },
      },
    },
    webpush: {
      notification: {
        tag: collapseId,
        icon: "/icons/Icon-192.png",
        badge: "/icons/Icon-192.png",
        title: publicTitle,
        body: publicBody,
        requireInteraction: isIncomingCall,
      },
    },
  };
}

module.exports = { buildPushMessage };
