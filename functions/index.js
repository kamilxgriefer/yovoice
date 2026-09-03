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
