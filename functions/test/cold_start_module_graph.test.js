const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const path = require("node:path");
const { test } = require("node:test");

// Four deploy-time contracts of functions/index.js, observed the only way
// they can be: by requiring the module in a fresh process. The module graph
// of a cold start is invisible once anything else in this process has loaded
// an SDK, and the export map is what `firebase deploy` reads — a renamed or
// dropped export is a NOT_FOUND on every client that calls it. The fourth is
// the source-static functions/servers graph: its exact cost and its 55 base
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

// Every export of functions/index.js, sorted. 296 names (293 + the three
// ADR-233 Premium Pages B5 exports below; 293 = 291 + the two
// ADR-233 Premium Pages B4 engagement exports below; 291 = 286 + the five
// ADR-233 Premium Pages B2 post exports below; 286 = 282 + the four
// ADR-233 Premium Pages B3 read callables below; 282 = 280 + the two
// ADR-233 Premium Pages B1 exports below; 280 = 274 + the three
// ADR-230 likers lists, the two ADR-230 comment-like toggles and the ADR-230
// "Hide my likes" setter below; build 36
// integration: 261 at the common base, +1 request to speak, +3 account
// takeover, +8 in-app bug reports; then +1 keep-warm pinger).
// 2026-09-26 (ADR-226, cost plan C3): keepWarmHotPathsSchedule joins the map
// — the one schedule that replaces every minInstances warm instance.
// 2026-09-25 (account-takeover Phase 1): onAuthUserCreated,
// secureFederatedSignInV1 and sweepFederatedTakeoverSchedule join the map —
// the unverified-password ledger trigger, the owner's post-sign-in
// remediation callable and its sweeper backstop.
// 2026-09-19 (ADR-213): onMomentCommentCreated/Deleted,
// onReelCommentCreated/Deleted and sendServerEventRemindersSchedule join the
// map — the comment-notification triggers and the Server event reminder
// worker. 2026-09-19 (ADR-180 amendment): releaseServerChannelSessionIfEmptyV1
// joins it too. 2026-09-19: the Server channel media and reaction callables
// join it as well. 2026-09-25 (request to speak): answerServerSessionHandV1,
// the host's decline of a raised hand, joins it as its own extension (261 ->
// 262 on its branch). 2026-09-25 (in-app bug reports): submitBugReportV1,
// attachBugReportScreenshotV1, listBugReportsV1, getBugReportV1,
// updateBugReportStatusV1 and sweepBugReportRetentionSchedule join it (261 +
// 6 = 267 on its branch). 2026-09-25 (bug report rights requests): the
// owner-only deleteBugReportV1 and deleteBugReportScreenshotV1 join it (267 +
// 2 = 269 on its branch). 2026-09-28 (ADR-230, "See who liked"):
// listVoiceMomentLikersV1 (Stage B), listReelLikersV1 (Reels) and
// listServerChannelMessageReactorsV1 (the Server message extension, outside
// the frozen 55-base manifest) join it; every one answers likersNotEnabled
// until appConfig/likersV1 is written. The comment-like toggles
// setMomentCommentLikeV1 (Stage B) and setReelCommentLikeV1 (Reels) join it
// too; they are deliberately NOT behind that switch, and neither is
// setMyLikesHiddenV1 (Profile), so people can opt out before any list is
// exposed. 2026-09-28 (ADR-233, Premium Pages package B1, 280 + 2 = 282):
// managePageV1 (answers pagesNotEnabled until appConfig/pagesV1 is written,
// except its safety op `pause`) and the badge trigger onPageBadgeSourceChanged
// join it. 2026-09-28 (ADR-233, package B3, 282 + 4 = 286): the read
// callables getPagesFeedV1, getPageV1, getPagePostV1 and findPagesV1 join it
// (every one answers pagesNotEnabled until appConfig/pagesV1 allows reading;
// none is warm or a keep-warm target). 2026-09-28 (ADR-233, package B2,
// 286 + 5 = 291): reservePagePostMediaV1, publishPagePostV1,
// managePagePostV1 and getPagePostMediaAccessV1 (all but the safety op
// `delete` and the audited staff media branch answer pagesNotEnabled until
// appConfig/pagesV1 admits the caller) and the scheduled worker
// pagesMaintenance join it; none is warm or a keep-warm target, and the
// Storage SDK stays lazy. 2026-09-28 (ADR-233, package B4, 291 + 2 =
// 293): pagePostEngagementV1 (like, unlike, comment; its safety op
// `deleteComment` never reads the switch) and listPagePostLikersV1 (behind
// appConfig/likersV1 AND appConfig/pagesV1) join it; neither is warm or a
// keep-warm target. 2026-09-28 (ADR-233, package B5, 293 + 3 = 296):
// createPageReportV1 (a safety action: it never reads appConfig/pagesV1) and
// the capability triggers onPageCapabilityEntitlementChanged and
// onPageCapabilityGrantChanged (one plain read and an early return for an
// account without a Page) join it; none is warm or a keep-warm target.
// `deliverBugReportV1` is NOT in it: both of its
// delivery channels are source-gated off in index.js. Extending this list is
// the deliberate review step the header describes, not a drive-by edit.
const EXPORT_NAMES = Object.freeze([
  "acceptDirectCall",
  "adminDeleteClub",
  "adminDeleteMessage",
  "adminDeleteRoom",
  "adminSetPremiumEntitlements",
  "answerServerSessionHandV1",
  "applySanction",
  "archiveServerChannelV1",
  "assignUserRole",
  "attachBugReportScreenshotV1",
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
  "createPageReportV1",
  "createReelComment",
  "createReelCommentReport",
  "createReelReport",
  "createRoom",
  "createServerBroadcastIngressV1",
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
  "deleteAccountSelfV1",
  "deleteBugReportScreenshotV1",
  "deleteBugReportV1",
  "deleteClubSelf",
  "deleteDirectConversationForMe",
  "deleteDirectMessage",
  "deleteMoment",
  "deleteMomentComment",
  "deleteReel",
  "deleteReelComment",
  "deleteRoomSelf",
  "deleteServerChannelMessageV1",
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
  "expireServerChannelMessageMediaReservations",
  "expireVoiceMomentsSchedule",
  "finalizeClubMedia",
  "finalizeDirectMessageAttachment",
  "finalizeMomentDraft",
  "finalizeProfileMediaUpload",
  "finalizeReelDraft",
  "finalizeReelDraftV2",
  "finalizeReelVoiceCommentDraft",
  "finalizeRoomCoverUpload",
  "finalizeServerChannelMessageMediaV1",
  "finalizeServerCompanyFileV1",
  "finalizeServerFamilyMemoryV1",
  "finalizeVoiceCommentDraft",
  "findPagesV1",
  "forceEndRoom",
  "getAdminAuditLog",
  "getAdminClub",
  "getAdminDashboard",
  "getAdminRoom",
  "getAuditLogFilters",
  "getBugReportV1",
  "getFriendSuggestions",
  "getGifCatalog",
  "getMutualFriends",
  "getMyStaffCapabilities",
  "getPagePostMediaAccessV1",
  "getPagePostV1",
  "getPageV1",
  "getPagesFeedV1",
  "getPremiumBillingContext",
  "getProfileMediaAccess",
  "getPublicBadges",
  "getReelMediaAccess",
  "getReelMediaAccessV2",
  "getReelViewV2",
  "getRoomCoverMediaAccess",
  "getServerChannelMessageMediaAccessV1",
  "getServerCompanyFileAccessV1",
  "getServerFamilyMemoryMediaAccessV1",
  "getStaffOverview",
  "getUserRole",
  "getVoiceMomentMediaAccess",
  "getVoiceMomentViewV2",
  "getVoiceMomentsFeedV2",
  "inventoryProfileMediaObjects",
  "joinServerV1",
  "keepWarmHotPathsSchedule",
  "leaveRoomSelf",
  "leaveServerV1",
  "listAdminAuditLogs",
  "listAdminClubs",
  "listAdminRooms",
  "listAdminUsers",
  "listBugReportsV1",
  "listPagePostLikersV1",
  "listReelLikersV1",
  "listReels",
  "listReelsV2",
  "listReportAuditTrail",
  "listServerChannelMessageReactorsV1",
  "listVoiceMomentLikersV1",
  "managePagePostV1",
  "managePageV1",
  "markDirectConversationRead",
  "migrateDirectIntegrityConversation",
  "migrateIntegrityMoment",
  "migrateIntegrityRoomCover",
  "migrateProfileMediaRecord",
  "moderateClubMessage",
  "moderateReport",
  "moderateRoomParticipantSelf",
  "onAccountDeletionOutboxCreated",
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
  "onAuthUserCreated",
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
  "onMomentCommentCreated",
  "onMomentCommentDeleted",
  "onNotificationCreated",
  "onPageBadgeSourceChanged",
  "onPageCapabilityEntitlementChanged",
  "onPageCapabilityGrantChanged",
  "onPinnedCreatorEntitlementChanged",
  "onPinnedCreatorProfileChanged",
  "onPinnedMomentEligibilityChanged",
  "onProfileIdentityChanged",
  "onReelCleanupOutboxCreated",
  "onReelCommentCreated",
  "onReelCommentDeleted",
  "onRoomLiveChanged",
  "onRoomLiveFanoutOutboxWritten",
  "onServerControlOutboxCreated",
  "onServerInviteWritten",
  "onUserBadgeSourceChanged",
  "onUserPrivacySourceChanged",
  "onVipGrantChanged",
  "openDirectConversation",
  "pagePostEngagementV1",
  "pagesMaintenance",
  "processAccountDeletionOutboxSchedule",
  "processPendingContentCleanupSchedule",
  "processPendingReelCleanupSchedule",
  "processPendingServerControlOutboxSchedule",
  "processServerChannelMessageMediaDeletionJobs",
  "publishPagePostV1",
  "publishPublicShowcaseSchedule",
  "publishPublicStatsSchedule",
  "receiveLiveKitAchievementWebhook",
  "reconcileAchievementsV1",
  "releaseServerChannelSessionIfEmptyV1",
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
  "reservePagePostMediaV1",
  "reserveProfileMediaUpload",
  "reserveReelDraft",
  "reserveReelDraftV2",
  "reserveReelVoiceCommentDraft",
  "reserveRoomCoverUpload",
  "reserveServerChannelMessageMediaV1",
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
  "secureFederatedSignInV1",
  "selectMyAchievementTitle",
  "sendClubInvite",
  "sendClubMessage",
  "sendDirectMessage",
  "sendFriendRequest",
  "sendRoomMessage",
  "sendServerEventRemindersSchedule",
  "setClubMemberBan",
  "setClubModerationStatus",
  "setCommunityServerFollowV1",
  "setCreatorAudienceEnabled",
  "setCreatorPinnedPost",
  "setDirectConversationPreference",
  "setDirectMessageReaction",
  "setDirectTyping",
  "setFollow",
  "setMomentCommentLikeV1",
  "setMomentLike",
  "setMyLikesHiddenV1",
  "setMyProfileVisibility",
  "setOwnRoomParticipantMute",
  "setParticipantMute",
  "setPremiumMessagingPrivacyV1",
  "setReelCommentLikeV1",
  "setReelLike",
  "setRoomModerationStatus",
  "setRoomStatusSelf",
  "setRoomVisibilitySelf",
  "setServerChannelAccessV1",
  "setServerChannelMessageReactionV1",
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
  "submitBugReportV1",
  "sweepBugReportRetentionSchedule",
  "sweepExpiredServerInvitesSchedule",
  "sweepFederatedTakeoverSchedule",
  "sweepServerCompanyFileMaintenanceSchedule",
  "sweepServerFamilyMemoryMaintenanceSchedule",
  "sweepStaleServerChannelSessionsSchedule",
  "sweepStrandedLiveRoomsSchedule",
  "transferClubOwnership",
  "transferClubOwnershipSelf",
  "transferServerOwnershipV1",
  "undoServerWhiteboardStrokeV1",
  "updateBugReportStatusV1",
  "updateMyDisplayName",
  "updateServerChannelV1",
  "updateServerEventV1",
  "updateServerListItemV1",
  "updateServerV1",
  "verifyPurchase",
]);

// The complete warm set — every export deployed with minInstances > 0 — and
// nothing else. Empty since ADR-226 (2026-09-26): each warm instance idled a
// full vCPU (about 30 PLN per 30 days at 256 MiB, 36 PLN at 512 MiB), ten of
// them were 93% of the bill, and together they served 91 requests in 7 days.
// The hot paths are kept warm by keepWarmHotPathsSchedule (ops/keep_warm.js)
// instead. Adding an entry here is a recurring charge and an owner decision.
const WARM_SET = Object.freeze([]);

// Static Servers registration deliberately loads this exact reviewed graph on
// every cold start. Pinning the file set makes an accidental eager provider SDK
// or a new Server subsystem visible here; the separate SDK assertion below
// protects the expensive/credentialed dependency boundary.
const COLD_START_SERVERS_MODULES = Object.freeze([
  "servers/authority.js",
  "servers/capacity.js",
  "servers/channels.js",
  "servers/community_broadcast.js",
  "servers/community_broadcast_cleanup.js",
  "servers/community_broadcast_contract.js",
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
  "servers/message_media.js",
  "servers/message_media_contract.js",
  "servers/message_reactions.js",
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

test("Servers exposes exactly 55 base exports and no Podcast recording surface", () => {
  assert.equal(inspectColdStart().serverExports.length, 55);
  assert.deepEqual(inspectColdStart().podcastRecordingExports, []);
});

test("no export keeps a warm instance", () => {
  assert.deepEqual(inspectColdStart().warm, WARM_SET.map((entry) => [...entry]));
});

test("every keep-warm target is a deployed export", () => {
  const { KEEP_WARM_TARGETS } = require("../ops/keep_warm");
  const exported = new Set(inspectColdStart().exportNames);
  for (const target of KEEP_WARM_TARGETS) {
    assert.ok(exported.has(target), `${target} is not exported`);
  }
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

// ADR-230: the likers modules are shared by the Voice (Stage B), Reel and
// Server message cold starts. In a fresh process they must add no SDK beyond
// the callable baseline (integrity/guards pulls firebase-functions/v2/https,
// which loads the firebase-admin app, auth and app-check cores): never the
// Firestore, Storage or Messaging SDKs, and never the direct-messaging graph
// (the reaction picker comes from the messaging/direct_reactions leaf).
// utils/likers_access is pure and loads no npm package at all.
const LIKERS_LOCAL_GRAPH = Object.freeze([
  "achievements/identity.js",
  "engagement/liker_audience.js",
  "engagement/liker_cursors.js",
  "engagement/likers_activation.js",
  "engagement/likers_admission.js",
  "engagement/likers_callable.js",
  "engagement/likers_paging.js",
  "integrity/guards.js",
  "messaging/direct_reactions.js",
  "profile/media_contract.js",
  "servers/authority.js",
  "servers/contract.js",
  "utils/likers_access.js",
  "utils/premium_access.js",
  "utils/roles.js",
]);

function inspectModuleGraph(modules) {
  const script = [
    `for (const name of ${JSON.stringify(modules)}) require(name);`,
    "const path = require('node:path');",
    "const cache = Object.keys(require.cache);",
    "const nodeModules = path.sep + 'node_modules' + path.sep;",
    "const packages = [...new Set(cache.filter((key) => key.includes(nodeModules))",
    "  .map((key) => { const rest = key.slice(key.lastIndexOf(nodeModules) + nodeModules.length).split(path.sep);",
    "    return rest[0].startsWith('@') ? rest.slice(0, 2).join('/') : rest[0]; }))].sort();",
    "const adminSubsystems = [...new Set(cache",
    "  .filter((key) => key.includes(nodeModules + 'firebase-admin' + path.sep + 'lib' + path.sep))",
    "  .map((key) => key.split(path.sep + 'lib' + path.sep)[1].split(path.sep)[0]))].sort();",
    "const local = cache.filter((key) => !key.includes(nodeModules))",
    "  .map((key) => path.relative(process.cwd(), key).split(path.sep).join('/')).sort();",
    "process.stdout.write(JSON.stringify({ packages, adminSubsystems, local }));",
  ].join(" ");
  return JSON.parse(execFileSync(process.execPath, ["-e", script], {
    cwd: FUNCTIONS_DIR,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }));
}

test("the likers modules load no SDK beyond the callable baseline", () => {
  const baseline = inspectModuleGraph(["./integrity/guards.js"]);
  const likers = inspectModuleGraph([
    "./engagement/likers_callable.js",
    "./engagement/comment_likes.js",
    "./utils/likers_access.js",
  ]);
  assert.deepEqual(likers.packages, baseline.packages);
  for (const subsystem of ["firestore", "storage", "messaging", "database"]) {
    assert.equal(
      likers.adminSubsystems.includes(subsystem),
      false,
      `the likers modules must not load firebase-admin/${subsystem}`,
    );
  }
  assert.deepEqual(
    likers.local.filter((file) => file !== "engagement/comment_likes.js"),
    [...LIKERS_LOCAL_GRAPH],
  );
  assert.equal(likers.local.includes("messaging/direct_integrity.js"), false);

  const access = inspectModuleGraph(["./utils/likers_access.js"]);
  assert.deepEqual(access.packages, []);
  assert.deepEqual(access.local, [
    "utils/likers_access.js",
    "utils/premium_access.js",
    "utils/roles.js",
  ]);
});

// ADR-233 (Premium Pages, B1 + B3 + B2 + B4 + B5): the gate, the activation switch,
// the contract, the catalog, the lapse function, the name filter, (B3) the
// audience predicate, the follow index, the post contract and the read wire
// contract, and (B2) the post write contract, the JPEG metadata walker and
// the Storage adapter (which receives its bucket; it never constructs one),
// and (B4) the engagement contract (link filter, like edge, bell-row ids,
// which the push trigger's source check loads lazily), and (B5) the report,
// moderation-notice and evidence-retention contract
// are the modules every later Pages package, setFollow and the
// profile hooks share. They add no SDK beyond the
// callable baseline (never Firestore or Storage: only visibility.js and the
// callable modules touch Firestore), and the catalog and the name filter load
// no npm package at all.
test("the shared Pages modules load no SDK beyond the callable baseline", () => {
  const baseline = inspectModuleGraph(["./integrity/guards.js"]);
  const shared = inspectModuleGraph([
    "./pages/access.js",
    "./pages/activation.js",
    "./pages/audience.js",
    "./pages/contract.js",
    "./pages/engagement_contract.js",
    "./pages/follows.js",
    "./pages/lapse.js",
    "./pages/media_contract.js",
    "./pages/media_probe.js",
    "./pages/media_storage.js",
    "./pages/post_contract.js",
    "./pages/report_contract.js",
    "./pages/views.js",
  ]);
  assert.deepEqual(shared.packages, baseline.packages);
  for (const subsystem of ["firestore", "storage", "messaging", "database"]) {
    assert.equal(
      shared.adminSubsystems.includes(subsystem),
      false,
      `the shared Pages modules must not load firebase-admin/${subsystem}`,
    );
  }
  for (const pure of ["./profile/name_safety.js", "./pages/catalog.js"]) {
    assert.deepEqual(inspectModuleGraph([pure]).packages, [], pure);
  }
});
