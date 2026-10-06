const SOUND_PROFILES = Object.freeze({
  message: Object.freeze({
    channelId: "yovoice_messages_v1",
    androidSound: "yovoice_message_v1",
    iosSound: "yovoice_message_v1.wav",
  }),
  social: Object.freeze({
    channelId: "yovoice_social_v1",
    androidSound: "yovoice_social_v1",
    iosSound: "yovoice_social_v1.wav",
  }),
  achievement: Object.freeze({
    channelId: "yovoice_achievements_v1",
    androidSound: "yovoice_achievement_v1",
    iosSound: "yovoice_achievement_v1.wav",
  }),
  alert: Object.freeze({
    channelId: "yovoice_alerts_v1",
    androidSound: "yovoice_alert_v1",
    iosSound: "yovoice_alert_v1.wav",
  }),
  call: Object.freeze({
    channelId: "yovoice_calls_v2",
    androidSound: "yovoice_call_v2",
    iosSound: "yovoice_call_v2.wav",
  }),
});

function soundProfileForNotification(type) {
  if (["directMessage", "mention", "reply", "commentMention"].includes(type)) {
    return SOUND_PROFILES.message;
  }
  if ([
    "friendRequest",
    "friendAccepted",
    "follow",
    "clubInvite",
    "clubInviteAccepted",
    "roomInvite",
    "broadcastInvite",
    "liveStarted",
    "momentComment",
    "reelComment",
    // ADR-233 §2.6: a comment on the recipient's Page post.
    "pagePostComment",
    // ADR-237: a Page the recipient follows published a post.
    "pagePostPublished",
    "serverRole",
  ].includes(type)) {
    return SOUND_PROFILES.social;
  }
  if (type === "achievementUnlocked") return SOUND_PROFILES.achievement;
  if (type === "directCall") return SOUND_PROFILES.call;
  // Listed explicitly rather than reached by the fallback below: a reminder
  // the member asked for is a time-sensitive alert, and naming it keeps the
  // choice deliberate when the fallback ever changes.
  if (type === "serverEventReminder") return SOUND_PROFILES.alert;
  return SOUND_PROFILES.alert;
}

// The generic lock-screen sentences, in English. The push boundary passes
// the recipient's language over them (push_locale.js); a slot it leaves out
// keeps the English sentence.
const DEFAULT_PUSH_SURFACE = Object.freeze({
  defaultBody: "Tap to open YO Voice",
  incomingCallTitle: "Incoming YO Voice call",
  incomingCallBody: "Open YO Voice to answer.",
  missedCallTitle: "Missed YO Voice call",
  missedCallBody: "Open YO Voice to view the call.",
});

// The ONLY types whose push may carry words somebody wrote. A followed
// Page's post is public to every signed-in reader, so its first line may
// appear on a lock screen. Every other type keeps the generic body whatever
// the caller passes: a comment's or a message's words never enter a push.
const PUSH_BODY_TYPES = Object.freeze(["pagePostPublished"]);
const PUSH_BODY_MAX = 240;

function pushSurface(surface) {
  const merged = { ...DEFAULT_PUSH_SURFACE };
  for (const key of Object.keys(DEFAULT_PUSH_SURFACE)) {
    const value = surface?.[key];
    if (typeof value === "string" && value.trim().length > 0) merged[key] = value;
  }
  return merged;
}

function buildPushMessage({
  tokens,
  type,
  targetId,
  actorId,
  notificationId,
  title,
  collapseId,
  targetSubId = null,
  body = null,
  surface = null,
}) {
  if (typeof collapseId !== "string" || collapseId.length === 0 ||
      collapseId.length > 64) {
    throw new TypeError("A valid platform collapse identifier is required.");
  }
  const isIncomingCall = type === "directCall";
  const isPrivateCallNotice = isIncomingCall || type === "missedCall";
  const soundProfile = soundProfileForNotification(type);
  const copy = pushSurface(surface);
  const authoredBody = PUSH_BODY_TYPES.includes(type) && typeof body === "string"
    ? body.trim().slice(0, PUSH_BODY_MAX)
    : "";
  const defaultBody = authoredBody.length > 0 ? authoredBody : copy.defaultBody;
  const publicTitle = isIncomingCall
    ? copy.incomingCallTitle
    : type === "missedCall"
      ? copy.missedCallTitle
      : title;
  const publicBody = isIncomingCall
    ? copy.incomingCallBody
    : type === "missedCall"
      ? copy.missedCallBody
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
      // Additive and optional: present only for types that carry a secondary
      // deep-link identity (a comment, a channel). Installed clients read the
      // four keys above and ignore this one.
      ...(typeof targetSubId === "string" && targetSubId.length > 0
        ? { targetSubId: targetSubId.slice(0, 128) }
        : {}),
    },
    android: {
      priority: "high",
      collapseKey: collapseId,
      notification: {
        tag: collapseId,
        channelId: soundProfile.channelId,
        sound: soundProfile.androidSound,
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
          sound: soundProfile.iosSound,
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

module.exports = {
  DEFAULT_PUSH_SURFACE,
  PUSH_BODY_TYPES,
  SOUND_PROFILES,
  buildPushMessage,
  soundProfileForNotification,
};
