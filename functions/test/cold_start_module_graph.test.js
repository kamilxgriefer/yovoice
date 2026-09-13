const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const path = require("node:path");
const { test } = require("node:test");

// Four deploy-time contracts of functions/index.js, observed the only way
// they can be: by requiring the module in a fresh process. The module graph
// of a cold start is invisible once anything else in this process has loaded
// an SDK, and the export map is what `firebase deploy` reads — a renamed or
// dropped export is a NOT_FOUND on every client that calls it. The fourth is
// the source-static functions/servers graph: its exact cost and its 53 base
// exports must change only in a deliberate, reviewed revision.

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
  "const registration = require('./servers/registration');",
  "const serverExports = registration.SERVERS_V1_EXPORT_NAMES",
  "  .filter((name) => Object.prototype.hasOwnProperty.call(exported, name)).sort();",
  "const podcastRecordingExports = registration.PODCAST_RECORDING_EXPORTS",
  "  .filter((name) => Object.prototype.hasOwnProperty.call(exported, name)).sort();",
  "const warm = [];",
  "for (const name of Object.keys(exported)) {",
  "  const endpoint = exported[name]?.__endpoint;",
  "  if (endpoint && Number.isSafeInteger(endpoint.minInstances) && endpoint.minInstances > 0) {",
  "    warm.push([name, endpoint.minInstances]);",
  "  }",
  "}",
  "process.stdout.write(JSON.stringify({",
  "  exportNames: Object.keys(exported).sort(),",
  "  serverExports,",
  "  podcastRecordingExports,",
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

function inspectColdStartWith(overrides = {}) {
  const env = { ...process.env };
  // The map below is the one deployed with functions/.env as it is today:
  // STRIPE_BILLING_EXPORTS unset. Enabling that rollout adds four Stripe
  // exports (functions/index.js) and must extend EXPORT_NAMES deliberately.
  delete env.STRIPE_BILLING_EXPORTS;
  // GIF and Servers export discovery is source-static. Delete obsolete or
  // late-loaded values for the baseline; a separate test proves that adding
  // them cannot change the exported names or Server module graph.
  delete env.GIF_PROVIDER;
  delete env.YOVOICE_SERVERS_V1;
  delete env.YOVOICE_PODCAST_RECORDING_ENABLED;
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
  Object.assign(env, overrides);
  return JSON.parse(execFileSync(process.execPath, ["-e", INSPECT], {
    cwd: FUNCTIONS_DIR,
    encoding: "utf8",
    env,
    stdio: ["ignore", "pipe", "ignore"],
  }));
}

function inspectColdStart() {
  if (inspection) return inspection;
  inspection = inspectColdStartWith();
  return inspection;
}

// Every export of functions/index.js, sorted. 245 names.
const EXPORT_NAMES = Object.freeze([
  "acceptDirectCall",
  "adminDeleteClub",
  "adminDeleteMessage",
  "adminDeleteRoom",
  "adminSetPremiumEntitlements",
  "applySanction",
  "archiveServerChannelV1",
  "assignUserRole",
  "bootstrapSuperAdmin",
  "cancelDirectCall",
  "cancelFriendRequest",
  "cancelServerEventV1",
  "cleanupProfileMediaUploads",
  "clearServerWhiteboardV1",
  "confirmCreatorAdultEligibility",
  "createCommunityClub",
  "createContentReport",
  "createDirectCallToken",
  "createLiveKitToken",
  "createMomentComment",
  "createReelComment",
  "createReelCommentReport",
  "createReelReport",
  "createRoom",
  "createServerChannelTokenV1",
  "createServerChannelV1",
  "createServerEventV1",
  "createServerFamilyCheckInV1",
  "createServerInviteV1",
  "createServerListItemV1",
  "createServerPodcastQuestionV1",
  "createServerV1",
  "createServerWhiteboardStrokeV1",
  "declineDirectCall",
  "deleteClubSelf",
  "deleteDirectConversationForMe",
  "deleteDirectMessage",
  "deleteMoment",
  "deleteMomentComment",
  "deleteReel",
  "deleteReelComment",
  "deleteRoomSelf",
  "deleteServerChannelV1",
  "deleteServerCompanyFileV1",
  "deleteServerFamilyCheckInV1",
  "deleteServerFamilyMemoryV1",
  "deleteServerListItemV1",
  "deleteServerV1",
  "editDirectMessage",
  "endDirectCall",
  "endRoomVoiceSelf",
  "endServerChannelSessionV1",
  "expireAbandonedDirectMessageAttachmentsSchedule",
  "expireAbandonedMomentDraftsSchedule",
  "expireAbandonedReelDraftsSchedule",
  "expireAbandonedReelVoiceCommentDraftsSchedule",
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
  "finalizeReelVoiceCommentDraft",
  "finalizeRoomCoverUpload",
  "finalizeServerCompanyFileV1",
  "finalizeServerFamilyMemoryV1",
  "finalizeVoiceCommentDraft",
  "forceEndRoom",
  "getAdminAuditLog",
  "getAdminClub",
  "getAdminDashboard",
  "getAdminRoom",
  "getAuditLogFilters",
  "getFriendSuggestions",
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
  "getServerCompanyFileAccessV1",
  "getServerFamilyMemoryMediaAccessV1",
  "getStaffOverview",
  "getUserRole",
  "getVoiceMomentMediaAccess",
  "getVoiceMomentViewV2",
  "getVoiceMomentsFeedV2",
  "inventoryProfileMediaObjects",
  "joinServerV1",
  "leaveRoomSelf",
  "leaveServerV1",
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
  "onServerControlOutboxCreated",
  "onServerInviteWritten",
  "onUserBadgeSourceChanged",
  "onUserPrivacySourceChanged",
  "onVipGrantChanged",
  "openDirectConversation",
  "processPendingContentCleanupSchedule",
  "processPendingReelCleanupSchedule",
  "processPendingServerControlOutboxSchedule",
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
  "removeServerMemberV1",
  "reorderServerChannelsV1",
  "reportGifAsset",
  "reserveDirectMessageAttachment",
  "reserveMomentDraft",
  "reserveProfileMediaUpload",
  "reserveReelDraft",
  "reserveReelDraftV2",
  "reserveReelVoiceCommentDraft",
  "reserveRoomCoverUpload",
  "reserveServerCompanyFileV1",
  "reserveServerFamilyMemoryV1",
  "reserveVoiceCommentDraft",
  "respondToFriendRequest",
  "respondToServerEventV1",
  "respondToServerInviteV1",
  "revokeMyRefreshTokens",
  "revokeServerInviteV1",
  "scanDirectIntegrityMigration",
  "scanMomentIntegrityMigration",
  "scanProfileMediaMigration",
  "scanRoomCoverIntegrityMigration",
  "scanRoomCoverObjectInventory",
  "scrubProfileIdentitySnapshots",
  "searchGifs",
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
  "setCommunityServerFollowV1",
  "setCreatorAudienceEnabled",
  "setCreatorPinnedPost",
  "setDirectConversationPreference",
  "setDirectMessageReaction",
  "setDirectTyping",
  "setFollow",
  "setMomentLike",
  "setMyProfileVisibility",
  "setOwnRoomParticipantMute",
  "setParticipantMute",
  "setPremiumMessagingPrivacyV1",
  "setReelLike",
  "setRoomModerationStatus",
  "setRoomStatusSelf",
  "setRoomVisibilitySelf",
  "setServerChannelAccessV1",
  "setServerMemberBanV1",
  "setServerMemberRoleV1",
  "setServerPodcastQuestionOnAirV1",
  "setServerPodcastQuestionVoteV1",
  "setServerSessionHandV1",
  "setServerSessionMuteV1",
  "setServerSessionParticipantRoleV1",
  "setUserBan",
  "setUserBlock",
  "startDirectCall",
  "startRoomVoice",
  "startServerChannelSessionV1",
  "sweepExpiredServerInvitesSchedule",
  "sweepServerCompanyFileMaintenanceSchedule",
  "sweepServerFamilyMemoryMaintenanceSchedule",
  "sweepStaleServerChannelSessionsSchedule",
  "sweepStrandedLiveRoomsSchedule",
  "transferClubOwnership",
  "transferClubOwnershipSelf",
  "transferServerOwnershipV1",
  "undoServerWhiteboardStrokeV1",
  "updateMyDisplayName",
  "updateServerChannelV1",
  "updateServerEventV1",
  "updateServerListItemV1",
  "updateServerV1",
  "verifyPurchase",
]);

// The complete warm set — every callable deployed with minInstances > 0 —
// and nothing else. Each entry is one always-on Cloud Run instance billed
// whether or not it serves a request (docs/DEPLOYMENT.md has the per-name
// cost). Call setup: startDirectCall, acceptDirectCall,
// createDirectCallToken and createLiveKitToken. Send paths: sendDirectMessage,
// sendRoomMessage.
// Chat open: openDirectConversation. Dormant-room join: startRoomVoice.
// Unmute: setOwnRoomParticipantMute. Reel publish: reserveReelDraftV2,
// finalizeReelDraftV2.
const WARM_SET = Object.freeze([
  ["acceptDirectCall", 1],
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

// Static Servers registration deliberately loads this exact reviewed graph on
// every cold start. Pinning the file set makes an accidental eager provider SDK
// or a new Server subsystem visible here; the separate SDK assertion below
// protects the expensive/credentialed dependency boundary.
const COLD_START_SERVERS_MODULES = Object.freeze([
  "servers/authority.js",
  "servers/capacity.js",
  "servers/channels.js",
  "servers/company_files.js",
  "servers/content_cleanup.js",
  "servers/contract.js",
  "servers/convergence.js",
  "servers/convergence_lifecycle.js",
  "servers/convergence_runtime.js",
  "servers/creation.js",
  "servers/documents.js",
  "servers/events.js",
  "servers/family_checkins.js",
  "servers/family_memories.js",
  "servers/follows.js",
  "servers/invites.js",
  "servers/management.js",
  "servers/memberships.js",
  "servers/operations.js",
  "servers/podcast_episodes.js",
  "servers/podcast_questions.js",
  "servers/registration.js",
  "servers/rtc_binding.js",
  "servers/session_authority.js",
  "servers/session_contract.js",
  "servers/session_control.js",
  "servers/session_livekit.js",
  "servers/session_participation.js",
  "servers/session_staleness.js",
  "servers/sessions.js",
  "servers/shared_list.js",
  "servers/templates.js",
  "servers/whiteboard.js",
]);

test("the source-static Servers cold-start module set is exactly pinned", () => {
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

test("Servers exposes exactly 53 base exports and no Podcast recording surface", () => {
  assert.equal(inspectColdStart().serverExports.length, 53);
  assert.deepEqual(inspectColdStart().podcastRecordingExports, []);
});

test("exactly the intended callables keep a warm instance", () => {
  assert.deepEqual(inspectColdStart().warm, WARM_SET.map((entry) => [...entry]));
});

test("late environment values cannot change the static Servers or GIF surface", () => {
  const baseline = inspectColdStart();
  for (const overrides of [
    { YOVOICE_SERVERS_V1: "enabled" },
    { YOVOICE_SERVERS_V1: "disabled" },
    { YOVOICE_SERVERS_V1: "enabled ", YOVOICE_PODCAST_RECORDING_ENABLED: "true" },
    { GIF_PROVIDER: "none" },
    { GIF_PROVIDER: "giphy", YOVOICE_SERVERS_V1: "true" },
  ]) {
    const changed = inspectColdStartWith(overrides);
    assert.deepEqual(changed.exportNames, baseline.exportNames, JSON.stringify(overrides));
    assert.deepEqual(changed.servers, baseline.servers, JSON.stringify(overrides));
    assert.deepEqual(changed.serverExports, baseline.serverExports, JSON.stringify(overrides));
    assert.deepEqual(changed.podcastRecordingExports, [], JSON.stringify(overrides));
  }
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
