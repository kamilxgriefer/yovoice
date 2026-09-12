const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

// Four deploy-time contracts of functions/index.js, observed the only way
// they can be: by requiring the module in a fresh process. The module graph
// of a cold start is invisible once anything else in this process has loaded
// an SDK, and the export map is what `firebase deploy` reads — a renamed or
// dropped export is a NOT_FOUND on every client that calls it. The fourth is
// the functions/servers set on that graph: the V1 runtime must stay off it
// while the gate is held.

const FUNCTIONS_DIR = path.resolve(__dirname, "..");

const INSPECT = [
  "require('./index.js');",
  "const exported = require('./index.js');",
  "const cache = Object.keys(require.cache);",
  "const loaded = (segment) => cache.filter((key) => key.includes(segment)).length;",
  "const path = require('node:path');",
  "const serversRoot = path.join(process.cwd(), 'servers') + path.sep;",
  "const servers = cache.filter((key) => key.startsWith(serversRoot))",
  "  .map((key) => path.relative(process.cwd(), key)).sort();",
  "const warm = [];",
  "for (const name of Object.keys(exported)) {",
  "  const endpoint = exported[name]?.__endpoint;",
  "  if (endpoint && Number.isSafeInteger(endpoint.minInstances) && endpoint.minInstances > 0) {",
  "    warm.push([name, endpoint.minInstances]);",
  "  }",
  "}",
  "process.stdout.write(JSON.stringify({",
  "  exportNames: Object.keys(exported).sort(),",
  "  servers,",
  "  warm: warm.sort((a, b) => a[0].localeCompare(b[0])),",
  "  sdk: {",
  "    livekit: loaded('/node_modules/livekit-server-sdk/'),",
  "    gcsStorage: loaded('/node_modules/@google-cloud/storage/'),",
  "    stripe: loaded('/node_modules/stripe/'),",
  "    musicMetadata: loaded('/node_modules/music-metadata/'),",
  "  },",
  "}));",
].join(" ");

let inspection = null;

function inspectColdStart() {
  if (inspection) return inspection;
  const env = { ...process.env };
  // The map below is the one deployed with functions/.env as it is today:
  // STRIPE_BILLING_EXPORTS unset. Enabling that rollout adds four Stripe
  // exports (functions/index.js) and must extend EXPORT_NAMES deliberately.
  delete env.STRIPE_BILLING_EXPORTS;
  // Same reasoning for the GIF rollout: the map below is the one deployed
  // with functions/.env as it is today (GIF_PROVIDER=none), which registers
  // getGifCatalog alone. Naming a provider adds searchGifs and
  // reportGifAsset and must extend EXPORT_NAMES deliberately.
  delete env.GIF_PROVIDER;
  // And for Servers V1 (ADR-176): functions/.env has no YOVOICE_SERVERS_V1, so
  // the map below has none of the sixteen V1 callables nor the two
  // serverControlOutbox dispatcher exports. The registration module and the V1
  // runtime stay off the cold-start graph; the three consumer-shared modules
  // below are on it by design and are asserted by name. `enabled` adds exactly
  // those eighteen names (test/servers_registration.test.js) and must extend
  // EXPORT_NAMES deliberately.
  delete env.YOVOICE_SERVERS_V1;
  // Never pretend to be the Cloud Run runtime: index.js emits its cold-start
  // log only there, and this child's stdout must stay pure JSON.
  delete env.K_SERVICE;
  delete env.FUNCTION_TARGET;
  delete env.FIREBASE_STORAGE_BUCKET;
  delete env.STORAGE_BUCKET;
  delete env.GCLOUD_STORAGE_BUCKET;
  env.GCLOUD_PROJECT = "yovoice-module-graph-test";
  env.FIREBASE_CONFIG = JSON.stringify({
    projectId: "yovoice-module-graph-test",
    storageBucket: "yovoice-module-graph-test.firebasestorage.app",
  });
  inspection = JSON.parse(execFileSync(process.execPath, ["-e", INSPECT], {
    cwd: FUNCTIONS_DIR,
    encoding: "utf8",
    env,
    stdio: ["ignore", "pipe", "ignore"],
  }));
  return inspection;
}

// Every export of functions/index.js, sorted. 181 names.
const EXPORT_NAMES = Object.freeze([
  "acceptDirectCall",
  "adminDeleteClub",
  "adminDeleteMessage",
  "adminDeleteRoom",
  "adminSetPremiumEntitlements",
  "applySanction",
  "assignUserRole",
  "bootstrapSuperAdmin",
  "cancelDirectCall",
  "cancelFriendRequest",
  "cleanupProfileMediaUploads",
  "createCommunityClub",
  "createContentReport",
  "createDirectCallToken",
  "createLiveKitToken",
  "createMomentComment",
  "createReelComment",
  "createReelCommentReport",
  "createReelReport",
  "createRoom",
  "declineDirectCall",
  "deleteClubSelf",
  "deleteDirectConversationForMe",
  "deleteDirectMessage",
  "deleteMoment",
  "deleteMomentComment",
  "deleteReel",
  "deleteReelComment",
  "deleteRoomSelf",
  "editDirectMessage",
  "endDirectCall",
  "endRoomVoiceSelf",
  "expireAbandonedDirectMessageAttachmentsSchedule",
  "expireAbandonedMomentDraftsSchedule",
  "expireAbandonedReelDraftsSchedule",
  "expireAbandonedVoiceCommentDraftsSchedule",
  "expireDirectCallsSchedule",
  "expirePremiumIdentity",
  "expirePublishedReelsSchedule",
  "expireRoomCoverUploadReservationsSchedule",
  "expireVoiceMomentsSchedule",
  "finalizeClubMedia",
  "finalizeDirectMessageAttachment",
  "finalizeMomentDraft",
  "finalizeProfileMediaUpload",
  "finalizeReelDraft",
  "finalizeReelDraftV2",
  "finalizeRoomCoverUpload",
  "finalizeVoiceCommentDraft",
  "forceEndRoom",
  "getAdminAuditLog",
  "getAdminClub",
  "getAdminDashboard",
  "getAdminRoom",
  "getAuditLogFilters",
  "getFriendSuggestions",
  // getGifCatalog binds NO secret, so it is registered whatever GIF_PROVIDER
  // says. searchGifs and reportGifAsset are absent from this list on purpose:
  // they bind GIPHY_API_KEY and register only once functions/.env names a real
  // provider, exactly like the four Stripe exports. Enabling that rollout must
  // extend this list deliberately.
  "getGifCatalog",
  "getMutualFriends",
  "getMyStaffCapabilities",
  "getPremiumBillingContext",
  "getProfileMediaAccess",
  "getPublicBadges",
  "getReelMediaAccess",
  "getReelMediaAccessV2",
  "getReelViewV2",
  "getRoomCoverMediaAccess",
  "getStaffOverview",
  "getUserRole",
  "getVoiceMomentMediaAccess",
  "getVoiceMomentViewV2",
  "getVoiceMomentsFeedV2",
  "inventoryProfileMediaObjects",
  "leaveRoomSelf",
  "listAdminAuditLogs",
  "listAdminClubs",
  "listAdminRooms",
  "listAdminUsers",
  "listReels",
  "listReelsV2",
  "listReportAuditTrail",
  "markDirectConversationRead",
  "migrateDirectIntegrityConversation",
  "migrateIntegrityMoment",
  "migrateIntegrityRoomCover",
  "migrateProfileMediaRecord",
  "moderateClubMessage",
  "moderateReport",
  "moderateRoomParticipantSelf",
  "onAchievementClubMemberCreated",
  "onAchievementClubMessageCreated",
  "onAchievementDirectMessageCreated",
  "onAchievementDirectReactionCreated",
  "onAchievementMomentLikeCreated",
  "onAchievementMomentPublished",
  "onAchievementOutboxCreated",
  "onAchievementRoomCreated",
  "onAchievementRoomMemberCreated",
  "onAchievementRoomMessageCreated",
  "onAchievementUserSocialCountersChanged",
  "onAuthUserDeleted",
  "onClubInviteCreated",
  "onClubMemberCreated",
  "onContentCleanupOutboxCreated",
  "onDirectCallControlCreated",
  "onDirectMessageCreated",
  "onDirectoryRestrictionChanged",
  "onDirectoryUserChanged",
  "onDirectoryVipGrantChanged",
  "onGlobalMessageModerated",
  "onModerationVoiceEnforcementCreated",
  "onNotificationCreated",
  "onPinnedCreatorEntitlementChanged",
  "onPinnedCreatorProfileChanged",
  "onPinnedMomentEligibilityChanged",
  "onProfileIdentityChanged",
  "onReelCleanupOutboxCreated",
  "onRoomLiveChanged",
  "onRoomLiveFanoutOutboxWritten",
  "onUserBadgeSourceChanged",
  "onUserPrivacySourceChanged",
  "onVipGrantChanged",
  "openDirectConversation",
  "processPendingContentCleanupSchedule",
  "processPendingReelCleanupSchedule",
  "publishPublicShowcaseSchedule",
  "publishPublicStatsSchedule",
  "receiveLiveKitAchievementWebhook",
  "reconcileAchievementsV1",
  "removeClubMember",
  "removeClubMemberSelf",
  "removeFriend",
  "removeReelComment",
  "removeRoomParticipant",
  "removeRoomParticipantSelf",
  "reserveDirectMessageAttachment",
  "reserveMomentDraft",
  "reserveProfileMediaUpload",
  "reserveReelDraft",
  "reserveReelDraftV2",
  "reserveRoomCoverUpload",
  "reserveVoiceCommentDraft",
  "respondToFriendRequest",
  "revokeMyRefreshTokens",
  "scanDirectIntegrityMigration",
  "scanMomentIntegrityMigration",
  "scanProfileMediaMigration",
  "scanRoomCoverIntegrityMigration",
  "scanRoomCoverObjectInventory",
  "scrubProfileIdentitySnapshots",
  "searchPublicProfiles",
  "searchUserDirectory",
  "selectMyAchievementTitle",
  "sendClubInvite",
  "sendClubMessage",
  "sendDirectMessage",
  "sendFriendRequest",
  "sendRoomMessage",
  "setClubMemberBan",
  "setClubModerationStatus",
  "setCreatorPinnedPost",
  "setDirectConversationPreference",
  "setDirectMessageReaction",
  "setDirectTyping",
  "setFollow",
  "setMomentLike",
  "setMyProfileVisibility",
  "setOwnRoomParticipantMute",
  "setParticipantMute",
  "setReelLike",
  "setRoomModerationStatus",
  "setRoomStatusSelf",
  "setRoomVisibilitySelf",
  "setUserBan",
  "setUserBlock",
  "startDirectCall",
  "startRoomVoice",
  "sweepStrandedLiveRoomsSchedule",
  "transferClubOwnership",
  "transferClubOwnershipSelf",
  "updateMyDisplayName",
  "verifyPurchase",
]);

// The complete warm set — every callable deployed with minInstances > 0 —
// and nothing else. Each entry is one always-on Cloud Run instance billed
// whether or not it serves a request (docs/DEPLOYMENT.md has the per-name
// cost). Call setup: createLiveKitToken, startDirectCall,
// createDirectCallToken. Send paths: sendDirectMessage, sendRoomMessage.
// Chat open: openDirectConversation. Dormant-room join: startRoomVoice.
// Unmute: setOwnRoomParticipantMute. Reel publish: reserveReelDraftV2,
// finalizeReelDraftV2.
const WARM_SET = Object.freeze([
  ["createDirectCallToken", 1],
  ["createLiveKitToken", 1],
  ["finalizeReelDraftV2", 1],
  ["openDirectConversation", 1],
  ["reserveReelDraftV2", 1],
  ["sendDirectMessage", 1],
  ["sendRoomMessage", 1],
  ["setOwnRoomParticipantMute", 1],
  ["startDirectCall", 1],
  ["startRoomVoice", 1],
]);

// The ONLY functions/servers modules a held cold start may load, and the
// reason each is there. They are consumer-shared leaves: pure, registering
// nothing and writing nothing, required at module scope by legacy consumers
// that must understand the V1 boundary.
//   servers/rtc_binding.js — livekit/sessions.js, staff/voice_enforcement.js,
//     achievements/livekit_http.js, rooms/liveness_sweeper.js, and the
//     per-room versioned-anchor guards in admin/clubs.js, clubs/deletion.js,
//     clubs/members.js and clubs/voice.js
//   servers/contract.js    — required by servers/rtc_binding.js
//   servers/capacity.js    — required by clubs/quota.js
// servers/registration.js and the V1 session runtime it pulls in are NOT on
// this list and must not join it: the gate in functions/index.js is what
// decides whether they load at all (ADR-176).
const COLD_START_SERVERS_MODULES = Object.freeze([
  "servers/capacity.js",
  "servers/contract.js",
  "servers/rtc_binding.js",
]);

test("exactly three functions/servers modules are on a held cold start", () => {
  // An eager require of the V1 runtime — a top-level require of
  // servers/registration.js, servers/sessions.js or servers/session_control.js
  // from anything index.js loads — fails HERE, before it can ship.
  assert.deepEqual(inspectColdStart().servers, [...COLD_START_SERVERS_MODULES]);
});

test("a cold start loads neither LiveKit, Cloud Storage, Stripe nor music-metadata", () => {
  // livekit-server-sdk is required on first use (livekit/sdk.js); the three
  // module-load Storage buckets are resolved on first object access
  // (utils/lazy_bucket.js, and profile/media_migration.js validates the
  // bucketName declaration rather than reading it); Stripe registers only
  // behind STRIPE_BILLING_EXPORTS; music-metadata is a dynamic import in the
  // Reel probe. If firebase-admin ever starts loading @google-cloud/storage
  // from require("firebase-admin/storage") itself, this fails here instead of
  // the lazy bucket silently recovering nothing.
  assert.deepEqual(inspectColdStart().sdk, {
    livekit: 0,
    gcsStorage: 0,
    stripe: 0,
    musicMetadata: 0,
  });
});

test("the deployed export map is exactly the pinned name list", () => {
  assert.deepEqual(inspectColdStart().exportNames, [...EXPORT_NAMES]);
});

test("exactly the intended callables keep a warm instance", () => {
  assert.deepEqual(inspectColdStart().warm, WARM_SET.map((entry) => [...entry]));
});

// Whether a single dotenv line assigns `name`. Comments are not assignments;
// `export NAME=` and padded names are.
function assignsEnvironment(line, name) {
  return new RegExp(`^\\s*(?:export\\s+)?${name}\\s*=`, "u").test(line);
}

test("no functions/.env file activates the Servers V1 gate", () => {
  // firebase-tools loads functions/.env, .env.<projectId>, .env.<projectAlias>
  // and — for the emulator only — .env.local, then deploys their contents as
  // the function environment (firebase-tools lib/functions/env.js). Every
  // other test in this file deletes YOVOICE_SERVERS_V1 from the child
  // environment, so none of them can see a value delivered that way: a single
  // committed `.env.yovoice-ec54a` line would register the eighteen Servers V1
  // functions (ADR-176) on the next deploy while this file still passed. This
  // is the only check that reads the files themselves.
  const names = fs.readdirSync(FUNCTIONS_DIR)
    .filter((name) => name === ".env" || name.startsWith(".env."))
    .sort();
  assert.ok(names.includes(".env"), "functions/.env must exist for this guard to mean anything");

  const offenders = [];
  for (const name of names) {
    const lines = fs.readFileSync(path.join(FUNCTIONS_DIR, name), "utf8").split(/\r?\n/u);
    for (const [index, line] of lines.entries()) {
      if (assignsEnvironment(line, "YOVOICE_SERVERS_V1")) offenders.push(`${name}:${index + 1}: ${line.trim()}`);
    }
  }
  assert.deepEqual(offenders, [], `Servers V1 is a held feature: ${offenders.join(", ")}`);

  // The matcher must actually be able to find an assignment, or the empty
  // result above proves nothing at all.
  assert.equal(assignsEnvironment("YOVOICE_SERVERS_V1=enabled", "YOVOICE_SERVERS_V1"), true);
  assert.equal(assignsEnvironment("  export YOVOICE_SERVERS_V1 = enabled", "YOVOICE_SERVERS_V1"), true);
  assert.equal(assignsEnvironment("# YOVOICE_SERVERS_V1=enabled", "YOVOICE_SERVERS_V1"), false);
  assert.equal(assignsEnvironment("YOVOICE_SERVERS_V1_EXTRA=enabled", "YOVOICE_SERVERS_V1"), false);
  // ...and it finds the switches functions/.env really does set today.
  const dotenv = fs.readFileSync(path.join(FUNCTIONS_DIR, ".env"), "utf8").split(/\r?\n/u);
  assert.ok(dotenv.some((line) => assignsEnvironment(line, "GIF_PROVIDER")), "functions/.env sets GIF_PROVIDER");
});

test("a missing Storage bucket still fails at load, not at the first upload", () => {
  // Before the media runtimes went lazy, getStorage().bucket() ran while
  // index.js was evaluated, so an unconfigured bucket broke `firebase deploy`
  // discovery. The lazy bucket removes that call; index.js asserts the same
  // precondition itself so the failure keeps happening at load time rather
  // than as a 500 on a user's first upload.
  const env = { ...process.env };
  delete env.FIREBASE_CONFIG;
  delete env.FIREBASE_STORAGE_BUCKET;
  delete env.STORAGE_BUCKET;
  delete env.GCLOUD_STORAGE_BUCKET;
  delete env.K_SERVICE;
  delete env.FUNCTION_TARGET;
  env.GCLOUD_PROJECT = "yovoice-module-graph-test";

  assert.throws(
    () => execFileSync(process.execPath, ["-e", "require('./index.js');"], {
      cwd: FUNCTIONS_DIR,
      encoding: "utf8",
      env,
      stdio: ["ignore", "ignore", "pipe"],
    }),
    (error) => {
      assert.match(error.stderr, /Bucket name not specified or invalid/u);
      return true;
    },
  );

  // ...and the same load succeeds as soon as a bucket is configured, so the
  // guard cannot be satisfied by an unrelated crash.
  execFileSync(process.execPath, ["-e", "require('./index.js');"], {
    cwd: FUNCTIONS_DIR,
    encoding: "utf8",
    env: {
      ...env,
      FIREBASE_CONFIG: JSON.stringify({
        projectId: "yovoice-module-graph-test",
        storageBucket: "yovoice-module-graph-test.firebasestorage.app",
      }),
    },
    stdio: ["ignore", "ignore", "pipe"],
  });
});
