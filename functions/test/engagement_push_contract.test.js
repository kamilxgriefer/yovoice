/**
 * The push contract for the notification types added on 2026-09-19
 * (ADR-212), and the deny-by-default rule that makes adding a type safe.
 *
 * Three things are asserted here and nowhere else:
 *   1. a type with no source validator is REFUSED at the push boundary.
 *      Before this change an unregistered type fell through to "return
 *      true" and pushed unrevalidated, which would have shipped a deleted
 *      comment's push to somebody's lock screen;
 *   2. every new type maps to a deliberate sound profile instead of
 *      silently inheriting the generic alert;
 *   3. the lock-screen body stays generic and `targetSubId` appears only
 *      when the row carries one — a comment's words never leave the app.
 */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();

const {
  SOUND_PROFILES,
  buildPushMessage,
  soundProfileForNotification,
} = require("../notifications/push_payload");
const {
  LEGACY_NOTIFICATION_TYPES,
  isRegisteredNotificationType,
  notificationSourceIsCurrent,
} = require("../notifications/social_source");
const { PUSH_TITLES } = require("../notifications/push");
const {
  ENGAGEMENT_NOTIFICATION_TYPES,
} = require("../notifications/engagement_source");

const FUNCTIONS_DIR = path.resolve(__dirname, "..");
const APP_DIR = path.resolve(FUNCTIONS_DIR, "..", "lib");
const readSource = (file) => fs.readFileSync(path.join(FUNCTIONS_DIR, file), "utf8");
const readApp = (file) => fs.readFileSync(path.join(APP_DIR, file), "utf8");

const NEW_TYPES = [
  "momentComment",
  "reelComment",
  "commentMention",
  "serverEventReminder",
  "serverRole",
];

test("an unregistered notification type is refused, not pushed", async () => {
  const neverRead = {
    doc: () => {
      throw new Error("an unregistered type must never read Firestore");
    },
    getAll: () => {
      throw new Error("an unregistered type must never read Firestore");
    },
  };
  for (const type of ["brandNewType", "momentLike", undefined, null]) {
    assert.equal(
      await notificationSourceIsCurrent({
        recipientId: "recipient",
        notificationId: "row",
        notification: { type, actorId: "actor" },
        firestore: neverRead,
      }),
      false,
      String(type),
    );
  }
  // Nothing that already shipped changed shape: every legacy type is still
  // routed to its historical validator (or its permissive default).
  assert.deepEqual([...LEGACY_NOTIFICATION_TYPES].sort(), [
    "achievementUnlocked", "broadcastInvite", "clubInvite",
    "clubInviteAccepted", "directCall", "directMessage", "follow",
    "friendAccepted", "friendRequest", "liveStarted", "mention", "missedCall",
    "moderation", "reply", "roomInvite", "system",
  ]);
  assert.deepEqual([...ENGAGEMENT_NOTIFICATION_TYPES].sort(), [...NEW_TYPES].sort());
});

test("every new type has a deliberate sound profile", () => {
  assert.equal(soundProfileForNotification("momentComment"), SOUND_PROFILES.social);
  assert.equal(soundProfileForNotification("reelComment"), SOUND_PROFILES.social);
  assert.equal(soundProfileForNotification("serverRole"), SOUND_PROFILES.social);
  assert.equal(
    soundProfileForNotification("commentMention"),
    SOUND_PROFILES.message,
  );
  assert.equal(
    soundProfileForNotification("serverEventReminder"),
    SOUND_PROFILES.alert,
  );
});

test("targetSubId rides along only when the row carries one", () => {
  const base = {
    tokens: ["token"],
    actorId: "actor",
    notificationId: "momentComment_comment-1",
    title: "Ada commented on your Moment",
    collapseId: "collapse-1",
  };
  const withSub = buildPushMessage({
    ...base,
    type: "momentComment",
    targetId: "moment-1",
    targetSubId: "comment-1",
  });
  assert.deepEqual(withSub.data, {
    type: "momentComment",
    targetId: "moment-1",
    actorId: "actor",
    notificationId: "momentComment_comment-1",
    targetSubId: "comment-1",
  });
  // The words of the comment are never in the payload; the lock screen says
  // the same generic sentence every non-call push says.
  assert.equal(withSub.notification.body, "Tap to open YO Voice");
  assert.equal(withSub.notification.title, base.title);
  assert.equal(withSub.android.notification.channelId, SOUND_PROFILES.social.channelId);

  const withoutSub = buildPushMessage({
    ...base,
    type: "friendRequest",
    targetId: "actor",
  });
  assert.equal(Object.hasOwn(withoutSub.data, "targetSubId"), false);
  const emptySub = buildPushMessage({
    ...base,
    type: "friendRequest",
    targetId: "actor",
    targetSubId: "",
  });
  assert.equal(Object.hasOwn(emptySub.data, "targetSubId"), false);
});

test("server and client copy stay in parity for every new type", () => {
  const push = readSource("notifications/push.js");
  const model = readApp("features/notifications/data/models/app_notification.dart");
  const screen = readApp(
    "features/notifications/presentation/screens/notifications_screen.dart",
  );
  const router = readApp("features/notifications/presentation/notification_router.dart");
  const preferences = readApp(
    "features/notifications/presentation/screens/notification_preferences_screen.dart",
  );
  for (const type of NEW_TYPES) {
    assert.match(push, new RegExp(`\\n  ${type}: \\(`, "u"), `${type} push title`);
    assert.match(model, new RegExp(`\\b${type}\\b`, "u"), `${type} client enum`);
    assert.match(
      screen,
      new RegExp(`NotificationType\\.${type}`, "u"),
      `${type} icon and in-app copy`,
    );
    assert.match(
      router,
      new RegExp(`NotificationType\\.${type}`, "u"),
      `${type} deep link`,
    );
  }
  // The single "Comments and mentions" toggle owns all three engagement
  // types; the Servers group owns the two Server types.
  assert.match(preferences, /NotificationType\.momentComment/u);
  assert.match(preferences, /NotificationType\.serverEventReminder/u);
  assert.match(preferences, /NotificationType\.serverRole/u);
  // A comment's text must not appear in any server-side push title.
  assert.doesNotMatch(push, /commentText|\$\{comment\}/u);
});

// Added 2026-09-20 (review round). The deny-by-default rule above is only
// safe because the push boundary DISTINGUISHES its two refusals. Both halves
// are pinned here.

test("every push title has a source validator", () => {
  const registered = new Set([
    ...LEGACY_NOTIFICATION_TYPES,
    ...ENGAGEMENT_NOTIFICATION_TYPES,
  ]);
  for (const type of Object.keys(PUSH_TITLES)) {
    // A type with a title but no validator used to reach the push
    // boundary's refusal path, which DELETES the recipient's bell row. The
    // boundary now skips instead of deleting, and this assertion keeps the
    // situation from arising at all.
    assert.ok(
      registered.has(type),
      `${type} has a push title but no source validator`,
    );
    assert.equal(isRegisteredNotificationType(type), true, type);
  }
  assert.equal(Object.keys(PUSH_TITLES).length, registered.size);
});

test("the registry predicate refuses anything nobody registered", () => {
  for (const type of ["brandNewType", "momentLike", "", undefined, null, 7]) {
    assert.equal(isRegisteredNotificationType(type), false, String(type));
  }
  assert.equal(isRegisteredNotificationType("serverEventReminder"), true);
  assert.equal(isRegisteredNotificationType("friendRequest"), true);
});
