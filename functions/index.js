const __moduleLoadStartedAt = process.hrtime.bigint();
const { getApps, initializeApp } = require("firebase-admin/app");

// Let the Admin SDK read the deployed project's canonical bucket from
// FIREBASE_CONFIG unless an operator intentionally supplies an override.
// New Firebase projects use `<project>.firebasestorage.app`; synthesizing the
// historical `<project>.appspot.com` name from GCLOUD_PROJECT silently points
// finalize/cleanup at a different bucket than the clients upload to.
const __storageBucketOverride =
  process.env.FIREBASE_STORAGE_BUCKET ||
  process.env.STORAGE_BUCKET ||
  process.env.GCLOUD_STORAGE_BUCKET;

if (!getApps().length) {
  initializeApp(
    __storageBucketOverride
      ? { storageBucket: __storageBucketOverride }
      : undefined,
  );
}

// Until the three media runtimes below went lazy (utils/lazy_bucket.js) they
// each called getStorage().bucket() while this module was evaluated, so a
// deployment with no bucket configured could not even be discovered: `node
// index.js` threw "Bucket name not specified or invalid". Resolving the bucket
// on first object access is what keeps @google-cloud/storage out of every cold
// start, but it would also turn that loud deploy-time failure into a 500 on the
// first user upload. Re-assert the precondition here, reading exactly the
// sources initializeApp reads and constructing nothing.
const __configuredStorageBucket = () => {
  if (__storageBucketOverride) return __storageBucketOverride;
  try {
    const config = JSON.parse(process.env.FIREBASE_CONFIG || "{}");
    return typeof config?.storageBucket === "string" ? config.storageBucket : "";
  } catch (_) {
    return "";
  }
};

if (!__configuredStorageBucket()) {
  throw new Error(
    "Bucket name not specified or invalid. Set FIREBASE_CONFIG.storageBucket " +
      "or FIREBASE_STORAGE_BUCKET before loading the Cloud Functions entry " +
      "point; the media runtimes resolve their bucket lazily and would " +
      "otherwise fail on the first upload instead of at deploy discovery.",
  );
}

/*
|--------------------------------------------------------------------------
| Admin
|--------------------------------------------------------------------------
*/

const {
  bootstrapSuperAdmin,
  assignUserRole,
  getUserRole,
  listAdminUsers,
  setUserBan,
} = require("./admin/users");

const { adminDeleteMessage } = require("./admin/messages");

const {
  listAdminRooms,
  getAdminRoom,
  setRoomModerationStatus,
  forceEndRoom,
  removeRoomParticipant,
  setParticipantMute,
  adminDeleteRoom,
} = require("./admin/rooms");

const { getAdminDashboard } = require("./admin/dashboard");

const {
  listAdminAuditLogs,
  getAdminAuditLog,
  getAuditLogFilters,
} = require("./admin/audit");

const {
  listAdminClubs,
  getAdminClub,
  setClubModerationStatus,
  removeClubMember,
  setClubMemberBan,
  transferClubOwnership,
  adminDeleteClub,
} = require("./admin/clubs");

/*
|--------------------------------------------------------------------------
| LiveKit
|--------------------------------------------------------------------------
*/

const { createLiveKitToken } = require("./livekit/token");
const {
  acceptDirectCall,
  cancelDirectCall,
  createDirectCallToken,
  declineDirectCall,
  endDirectCall,
  expireDirectCallsSchedule,
  onDirectCallControlCreated,
  startDirectCall,
} = require("./calls/direct_calls");

/*
|--------------------------------------------------------------------------
| Friends
|--------------------------------------------------------------------------
*/

const {
  getMutualFriends,
  getFriendSuggestions,
  sendFriendRequest,
  respondToFriendRequest,
  cancelFriendRequest,
  removeFriend,
  setFollow,
  setUserBlock,
} = require("./friends/social_graph");

/*
|--------------------------------------------------------------------------
| Clubs (self-service)
|--------------------------------------------------------------------------
*/

const {
  createCommunityClub,
  finalizeClubMedia,
} = require("./clubs/creation");
const { removeClubMemberSelf } = require("./clubs/members");
const { transferClubOwnershipSelf } = require("./clubs/ownership");
const { moderateClubMessage } = require("./clubs/message_moderation");
// Owner-initiated permanent Club deletion — the "Club lifecycle" that
// deleteRoomSelf's lounge refusal routes to. Tears down the club document
// tree, its lounge room, LiveKit state, projections and Storage media.
const { deleteClubSelf } = require("./clubs/deletion");
const {
  deleteRoomSelf,
  endRoomVoiceSelf,
  leaveRoomSelf,
  moderateRoomParticipantSelf,
  removeRoomParticipantSelf,
  setOwnRoomParticipantMute,
  setRoomStatusSelf,
} = require("./rooms/participants");
// The only repair for a room stranded live with an empty roster — the
// start→join window in RoomVoiceEntryCoordinator, and any process death
// inside it. No client can fix that state: `leaveRoomSelf` returns early
// without a participant row, and granting it the repair would hand every
// signed-in account a lever to drop `isLive` on somebody else's room.
const {
  sweepStrandedLiveRoomsSchedule,
} = require("./rooms/liveness_sweeper");

/*
|--------------------------------------------------------------------------
| Notifications
|--------------------------------------------------------------------------
*/

const { onNotificationCreated } = require("./notifications/push");
const {
  onDirectMessageCreated,
  onRoomLiveFanoutOutboxWritten,
  onRoomLiveChanged,
} = require("./notifications/activity");
const {
  sendClubInvite,
  onClubInviteCreated,
  onClubMemberCreated,
} = require("./notifications/invites");

/*
|--------------------------------------------------------------------------
| User Management
|--------------------------------------------------------------------------
*/

exports.bootstrapSuperAdmin = bootstrapSuperAdmin;
exports.assignUserRole = assignUserRole;
exports.getUserRole = getUserRole;
exports.listAdminUsers = listAdminUsers;
exports.setUserBan = setUserBan;
exports.adminDeleteMessage = adminDeleteMessage;

/*
|--------------------------------------------------------------------------
| Dashboard
|--------------------------------------------------------------------------
*/

exports.getAdminDashboard = getAdminDashboard;

/*
|--------------------------------------------------------------------------
| Rooms
|--------------------------------------------------------------------------
*/

exports.listAdminRooms = listAdminRooms;
exports.getAdminRoom = getAdminRoom;
exports.setRoomModerationStatus = setRoomModerationStatus;
exports.forceEndRoom = forceEndRoom;
exports.removeRoomParticipant = removeRoomParticipant;
exports.setParticipantMute = setParticipantMute;
exports.adminDeleteRoom = adminDeleteRoom;

/*
|--------------------------------------------------------------------------
| Clubs
|--------------------------------------------------------------------------
*/

exports.listAdminClubs = listAdminClubs;
exports.getAdminClub = getAdminClub;
exports.setClubModerationStatus = setClubModerationStatus;
exports.removeClubMember = removeClubMember;
exports.setClubMemberBan = setClubMemberBan;
exports.transferClubOwnership = transferClubOwnership;
exports.adminDeleteClub = adminDeleteClub;

/*
|--------------------------------------------------------------------------
| Audit
|--------------------------------------------------------------------------
*/

exports.listAdminAuditLogs = listAdminAuditLogs;
exports.getAdminAuditLog = getAdminAuditLog;
exports.getAuditLogFilters = getAuditLogFilters;

/*
|--------------------------------------------------------------------------
| LiveKit
|--------------------------------------------------------------------------
*/

exports.createLiveKitToken = createLiveKitToken;
exports.startDirectCall = startDirectCall;
exports.acceptDirectCall = acceptDirectCall;
exports.declineDirectCall = declineDirectCall;
exports.cancelDirectCall = cancelDirectCall;
exports.endDirectCall = endDirectCall;
exports.createDirectCallToken = createDirectCallToken;
exports.expireDirectCallsSchedule = expireDirectCallsSchedule;
exports.onDirectCallControlCreated = onDirectCallControlCreated;

/*
|--------------------------------------------------------------------------
| Friends
|--------------------------------------------------------------------------
*/

exports.getMutualFriends = getMutualFriends;
exports.getFriendSuggestions = getFriendSuggestions;
exports.sendFriendRequest = sendFriendRequest;
exports.respondToFriendRequest = respondToFriendRequest;
exports.cancelFriendRequest = cancelFriendRequest;
exports.removeFriend = removeFriend;
exports.setFollow = setFollow;
exports.setUserBlock = setUserBlock;
exports.moderateClubMessage = moderateClubMessage;

/*
|--------------------------------------------------------------------------
| Clubs (self-service)
|--------------------------------------------------------------------------
*/

exports.transferClubOwnershipSelf = transferClubOwnershipSelf;
// Owner-only permanent Club deletion ({ clubId }): deletes the club and its
// lounge room in one lifecycle. This is the callable the room delete flow
// invokes when the deleted "room" is a Club Lounge.
exports.deleteClubSelf = deleteClubSelf;
exports.createCommunityClub = createCommunityClub;
exports.finalizeClubMedia = finalizeClubMedia;
exports.removeClubMemberSelf = removeClubMemberSelf;
exports.removeRoomParticipantSelf = removeRoomParticipantSelf;
exports.setOwnRoomParticipantMute = setOwnRoomParticipantMute;
exports.moderateRoomParticipantSelf = moderateRoomParticipantSelf;
exports.setRoomStatusSelf = setRoomStatusSelf;
exports.endRoomVoiceSelf = endRoomVoiceSelf;
exports.leaveRoomSelf = leaveRoomSelf;
exports.deleteRoomSelf = deleteRoomSelf;
exports.sweepStrandedLiveRoomsSchedule = sweepStrandedLiveRoomsSchedule;

/*
|--------------------------------------------------------------------------
| Notifications
|--------------------------------------------------------------------------
*/

exports.onNotificationCreated = onNotificationCreated;
exports.onDirectMessageCreated = onDirectMessageCreated;
exports.onRoomLiveFanoutOutboxWritten = onRoomLiveFanoutOutboxWritten;
exports.onRoomLiveChanged = onRoomLiveChanged;
exports.sendClubInvite = sendClubInvite;
exports.onClubInviteCreated = onClubInviteCreated;
exports.onClubMemberCreated = onClubMemberCreated;

/*
|--------------------------------------------------------------------------
| Account sessions
|--------------------------------------------------------------------------
*/

const {
  revokeMyRefreshTokens,
} = require("./auth/session_management");

exports.revokeMyRefreshTokens = revokeMyRefreshTokens;

/*
|--------------------------------------------------------------------------
| Profile
|--------------------------------------------------------------------------
*/

const { onProfileIdentityChanged } = require("./profile/fanout");
const { updateMyDisplayName } = require("./profile/display_name");
const { setMyProfileVisibility } = require("./profile/profile_visibility");
const {
  onAuthUserDeleted,
  onUserPrivacySourceChanged,
  searchPublicProfiles,
} = require("./profile/public_profiles");

exports.onProfileIdentityChanged = onProfileIdentityChanged;
exports.updateMyDisplayName = updateMyDisplayName;
exports.setMyProfileVisibility = setMyProfileVisibility;
exports.onAuthUserDeleted = onAuthUserDeleted;
exports.onUserPrivacySourceChanged = onUserPrivacySourceChanged;
exports.searchPublicProfiles = searchPublicProfiles;

// Private avatar/banner media. New uploads are reservation-bound and never
// persist a Firebase download-token URL; readers receive a generation-bound
// V4 grant only after the profile visibility, bilateral friendship (when
// required), blocks and both account states are rechecked server-side.
const { createProfileMediaFunctions } = require("./profile/media_runtime");
Object.assign(exports, createProfileMediaFunctions());

/*
|--------------------------------------------------------------------------
| Moderation
|--------------------------------------------------------------------------
*/

const { onGlobalMessageModerated } = require("./moderation/global_chat");
const { moderateReport } = require("./moderation/reports");
const { listReportAuditTrail } = require("./moderation/report_audit");

exports.onGlobalMessageModerated = onGlobalMessageModerated;
exports.moderateReport = moderateReport;
exports.listReportAuditTrail = listReportAuditTrail;

/*
|--------------------------------------------------------------------------
| Public badges (derived mirror — see badges/public_badges.js)
|--------------------------------------------------------------------------
*/

const {
  onUserBadgeSourceChanged,
  onVipGrantChanged,
  getPublicBadges,
} = require("./badges/public_badges");

exports.onUserBadgeSourceChanged = onUserBadgeSourceChanged;
exports.onVipGrantChanged = onVipGrantChanged;
exports.getPublicBadges = getPublicBadges;

const { getMyStaffCapabilities } = require("./staff/capabilities");

exports.getMyStaffCapabilities = getMyStaffCapabilities;

const { applySanction } = require("./staff/sanctions");
const {
  onModerationVoiceEnforcementCreated,
} = require("./staff/voice_enforcement");

exports.applySanction = applySanction;
exports.onModerationVoiceEnforcementCreated =
  onModerationVoiceEnforcementCreated;

/*
|--------------------------------------------------------------------------
| Staff directory & overview (owner-only — see staff/directory.js)
|--------------------------------------------------------------------------
*/

const {
  onDirectoryUserChanged,
  onDirectoryVipGrantChanged,
  onDirectoryRestrictionChanged,
  searchUserDirectory,
} = require("./staff/directory");

exports.onDirectoryUserChanged = onDirectoryUserChanged;
exports.onDirectoryVipGrantChanged = onDirectoryVipGrantChanged;
exports.onDirectoryRestrictionChanged = onDirectoryRestrictionChanged;
exports.searchUserDirectory = searchUserDirectory;

const { getStaffOverview } = require("./staff/overview");

exports.getStaffOverview = getStaffOverview;

/*
|--------------------------------------------------------------------------
| Public statistics (server-owned publicStats/live — see stats/public_stats.js)
|--------------------------------------------------------------------------
*/

const { publishPublicStatsSchedule } = require("./stats/public_stats");

exports.publishPublicStatsSchedule = publishPublicStatsSchedule;

/*
|--------------------------------------------------------------------------
| Public marketing showcase (consent-backed publicShowcase/live)
|--------------------------------------------------------------------------
*/

const {
  publishPublicShowcaseSchedule,
} = require("./marketing/public_showcase");

exports.publishPublicShowcaseSchedule = publishPublicShowcaseSchedule;

/*
|--------------------------------------------------------------------------
| Premium
|--------------------------------------------------------------------------
*/

const {
  adminSetPremiumEntitlements,
  verifyPurchase,
  expirePremiumIdentity,
} = require("./premium/entitlements");
const {
  getPremiumBillingContext,
} = require("./premium/billing_context");
// Secret-bound Stripe mutations register only when the operator explicitly
// turns the rollout on (functions/.env: STRIPE_BILLING_EXPORTS=enabled).
// Requiring that module during deploy discovery registers its parameters and
// secrets, so keeping it behind the rollout flag lets the independent public
// catalog deploy even before provider configuration is complete.
const stripeBillingEnabled =
  process.env.STRIPE_BILLING_EXPORTS === "enabled";
const { createStageBFunctions } = require("./integrity/stage_b_functions");
const {
  onAchievementClubMemberCreated,
  onAchievementClubMessageCreated,
  onAchievementDirectMessageCreated,
  onAchievementDirectReactionCreated,
  onAchievementMomentLikeCreated,
  onAchievementMomentPublished,
  onAchievementOutboxCreated,
  onAchievementRoomCreated,
  onAchievementRoomMemberCreated,
  onAchievementRoomMessageCreated,
  onAchievementUserSocialCountersChanged,
} = require("./achievements/triggers");
const { selectMyAchievementTitle } = require("./achievements/callables");
const { reconcileAchievementsV1 } = require("./achievements/migration");
// The only writer of connected voice time. Until this was exported the whole
// AchievementCategory.voice group and the Creator Studio speaking/hosting
// tiles were permanently zero: nothing else in the project produces a
// voiceSeconds or hostSeconds event. Signed LiveKit deliveries only — see
// achievements/livekit_http.js for the authentication boundary.
const {
  receiveLiveKitAchievementWebhook,
} = require("./achievements/livekit_http");

exports.adminSetPremiumEntitlements = adminSetPremiumEntitlements;
exports.verifyPurchase = verifyPurchase;
exports.expirePremiumIdentity = expirePremiumIdentity;
// The public catalog never binds provider secrets. It remains available with
// checkoutAvailable=false even while the secret-bound payment endpoints are
// disabled, so clients can render Premium without fabricating availability.
exports.getPremiumBillingContext = getPremiumBillingContext;
if (stripeBillingEnabled) {
  const {
    createPremiumCheckoutSession,
    createPremiumPortalSession,
    stripePremiumWebhook,
    onAuthUserDeletedCancelStripe,
  } = require("./premium/stripe_billing");
  exports.createPremiumCheckoutSession = createPremiumCheckoutSession;
  exports.createPremiumPortalSession = createPremiumPortalSession;
  exports.stripePremiumWebhook = stripePremiumWebhook;
  exports.onAuthUserDeletedCancelStripe = onAuthUserDeletedCancelStripe;
}

// Creator Studio pinned posts are references to canonical, published Voice
// Moments. The callable is the only writer; the trigger removes a pin as soon
// as its Moment becomes ineligible or is deleted.
const {
  onPinnedCreatorEntitlementChanged,
  onPinnedCreatorProfileChanged,
  onPinnedMomentEligibilityChanged,
  setCreatorPinnedPost,
} = require("./creator/pinned_posts");

exports.setCreatorPinnedPost = setCreatorPinnedPost;
exports.onPinnedMomentEligibilityChanged = onPinnedMomentEligibilityChanged;
exports.onPinnedCreatorEntitlementChanged = onPinnedCreatorEntitlementChanged;
exports.onPinnedCreatorProfileChanged = onPinnedCreatorProfileChanged;

// The server half of Voice Moment expiry. finalizeMomentDraft stamps
// `expiresAt = createdAt + availability` on every expiring publish (the
// operator-chosen availability window, 24h by default; a "permanent"
// publish writes no deadline and is never swept); this schedule is what
// actually retires a Moment once that deadline passes — the client's
// `expiresAt > now` feed filter (missing = permanent = visible) only papers
// over the at-most-10-minute sweep gap and must never be the sole
// enforcement. The flip is exactly
// { isPublished: false, status: "expired", updatedAt }: audio, caption,
// counters, likes, comments and reports all stay, and only the author's own
// delete removes anything. Requires the deployed (isPublished ASC,
// expiresAt ASC) composite on voiceMoments — run the query in production
// after deploying (ADR-007).
const { expireVoiceMomentsSchedule } = require("./moments/expiry");

exports.expireVoiceMomentsSchedule = expireVoiceMomentsSchedule;

function strictBooleanEnvironment(name) {
  const value = String(process.env[name] ?? "").trim().toLowerCase();
  if (value === "" || value === "false") return false;
  if (value === "true") return true;
  throw new Error(`${name} must be exactly true or false.`);
}

const { createReelFunctions } = require("./reels");
Object.assign(exports, createReelFunctions({
  // Clients attach App Check tokens already. Enforcement follows the staged
  // project-wide rollout and must not be enabled before platform telemetry is
  // healthy on iOS, Android and Web.
  enforceAppCheck: strictBooleanEnvironment(
    "YOVOICE_ENFORCE_REELS_APP_CHECK",
  ),
}));

// GIFs in the composer (ADR-167). `getGifCatalog` binds no secret and is
// always registered, so a client can be told the feature is unavailable
// instead of guessing; `searchGifs` and `reportGifAsset` bind GIPHY_API_KEY
// and therefore register only when functions/.env names a real provider —
// the same shape as the Stripe rollout above, and for the same reason:
// defineSecret requires the secret to exist at deploy time, and deploy
// discovery has to keep working before the key does.
const { createGifFunctions } = require("./media/gif/catalog");
Object.assign(exports, createGifFunctions({
  // Clients attach App Check tokens already. Enforcement follows the staged
  // project-wide rollout used by Reels and Stage B.
  enforceAppCheck: strictBooleanEnvironment(
    "YOVOICE_ENFORCE_GIF_APP_CHECK",
  ),
}));

const stageBFunctions = createStageBFunctions({
  // Rollout switch: clients already attach App Check tokens, but production
  // enforcement must only flip after Android/iOS/Web attestation telemetry
  // is healthy. Invalid configuration fails the deployment instead of
  // silently weakening enforcement.
  enforceUserAppCheck: strictBooleanEnvironment(
    "YOVOICE_ENFORCE_STAGE_B_APP_CHECK",
  ),
  enforceMigrationAppCheck: strictBooleanEnvironment(
    "YOVOICE_ENFORCE_MIGRATION_APP_CHECK",
  ),
});
Object.assign(exports, stageBFunctions);

exports.selectMyAchievementTitle = selectMyAchievementTitle;
exports.onAchievementClubMemberCreated = onAchievementClubMemberCreated;
exports.onAchievementClubMessageCreated = onAchievementClubMessageCreated;
exports.onAchievementDirectMessageCreated = onAchievementDirectMessageCreated;
exports.onAchievementDirectReactionCreated = onAchievementDirectReactionCreated;
exports.onAchievementMomentLikeCreated = onAchievementMomentLikeCreated;
exports.onAchievementMomentPublished = onAchievementMomentPublished;
exports.onAchievementOutboxCreated = onAchievementOutboxCreated;
exports.onAchievementRoomCreated = onAchievementRoomCreated;
exports.onAchievementRoomMemberCreated = onAchievementRoomMemberCreated;
exports.onAchievementRoomMessageCreated = onAchievementRoomMessageCreated;
exports.onAchievementUserSocialCountersChanged =
  onAchievementUserSocialCountersChanged;
exports.reconcileAchievementsV1 = reconcileAchievementsV1;
exports.receiveLiveKitAchievementWebhook = receiveLiveKitAchievementWebhook;

/*
|--------------------------------------------------------------------------
| Servers V1 — registration and durable dispatch gate (ADR-176)
|--------------------------------------------------------------------------
| YOVOICE_SERVERS_V1 is absent from functions/.env today, so nothing in this
| block runs: the registration module and the whole V1 runtime stay OFF the
| cold-start module graph, and the export map stays exactly the one pinned by
| test/cold_start_module_graph.test.js. Three functions/servers modules are on
| that graph by design, and always were: servers/rtc_binding.js (required by
| livekit/sessions.js, staff/voice_enforcement.js, achievements/livekit_http.js
| and rooms/liveness_sweeper.js), servers/contract.js (from rtc_binding.js) and
| servers/capacity.js (from clubs/quota.js). They register nothing, write
| nothing and load no SDK; that exact set is asserted by
| test/cold_start_module_graph.test.js, so an eager require of the runtime
| fails there rather than shipping. `enabled` registers the twenty-one V1
| callables of docs/Servers.md "Callable contract" plus the serverControlOutbox
| trigger, its bounded retry schedule and the stale-generation sweep
| (servers/registration.js). `disabled`
| and absent are equivalent; any other value — including a case or whitespace
| variant such as `enabled ` — fails deploy discovery and the cold start, so a
| typo can never silently ship or silently hold the feature. The gate registers
| endpoints only: every server created through them stays
| `serverActivationState: held`, because no activation writer exists
| (docs/Servers.md, "Sessions") — that is a separate reviewed slice, not a
| value of this variable.
*/

function strictEnabledEnvironment(name) {
  // Deliberately no trim and no case folding, unlike strictBooleanEnvironment
  // above: this switch decides whether twenty-four functions exist at all, so the
  // value must be byte-for-byte `enabled`, `disabled`, empty or absent. A
  // whitespace or case variant such as `enabled ` is a typo in functions/.env,
  // never an authorization to ship the surface, and it fails deploy discovery
  // and the cold start instead of silently loading.
  const value = String(process.env[name] ?? "");
  if (value === "" || value === "disabled") return false;
  if (value === "enabled") return true;
  throw new Error(`${name} must be exactly enabled or disabled.`);
}

if (strictEnabledEnvironment("YOVOICE_SERVERS_V1")) {
  const { createServersV1Functions } = require("./servers/registration");
  Object.assign(exports, createServersV1Functions({
    // Staged App Check enforcement, same rollout convention as Reels, GIFs
    // and Stage B. Read only inside the gate: the switch has no meaning while
    // the endpoints are not registered, and an unset value stays false.
    enforceAppCheck: strictBooleanEnvironment(
      "YOVOICE_ENFORCE_SERVERS_APP_CHECK",
    ),
  }));
}

// Cold-start observability. Emitted once per instance start, only inside the
// Cloud Run / Functions runtime (K_SERVICE and FUNCTION_TARGET are set there
// and nowhere else): tests that require this module in a child process read
// its stdout, and deploy discovery has nothing to measure. Logs Explorer:
// jsonPayload.message="functions module evaluated" grouped by
// jsonPayload.functionTarget is the before/after for any change to the module
// graph above — nothing else measures it.
if (process.env.K_SERVICE || process.env.FUNCTION_TARGET) {
  require("firebase-functions/v2").logger.info("functions module evaluated", {
    moduleLoadMs: Number(
      (process.hrtime.bigint() - __moduleLoadStartedAt) / 1000000n,
    ),
    functionTarget: process.env.FUNCTION_TARGET ?? null,
  });
}
