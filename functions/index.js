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
const {
  deleteRoomSelf,
  endRoomVoiceSelf,
  leaveRoomSelf,
  moderateRoomParticipantSelf,
  removeRoomParticipantSelf,
  setOwnRoomParticipantMute,
  setRoomStatusSelf,
} = require("./rooms/participants");

/*
|--------------------------------------------------------------------------
| Notifications
|--------------------------------------------------------------------------
*/

const { onNotificationCreated } = require("./notifications/push");
// Friend request / acceptance / follow notifications are derived from
// the authoritative source documents (ADR-041) rather than written by
// the acting client.
const {
  onFriendRequestCreated,
  onFriendRequestResolved,
  onFollowerCreated,
} = require("./notifications/social");
const {
  onDirectMessageCreated,
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

/*
|--------------------------------------------------------------------------
| Clubs (self-service)
|--------------------------------------------------------------------------
*/

exports.transferClubOwnershipSelf = transferClubOwnershipSelf;
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

/*
|--------------------------------------------------------------------------
| Notifications
|--------------------------------------------------------------------------
*/

exports.onNotificationCreated = onNotificationCreated;
exports.onFriendRequestCreated = onFriendRequestCreated;
exports.onFriendRequestResolved = onFriendRequestResolved;
exports.onFollowerCreated = onFollowerCreated;
exports.onDirectMessageCreated = onDirectMessageCreated;
exports.onRoomLiveChanged = onRoomLiveChanged;
exports.sendClubInvite = sendClubInvite;
exports.onClubInviteCreated = onClubInviteCreated;
exports.onClubMemberCreated = onClubMemberCreated;

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
  createPremiumCheckoutSession,
  createPremiumPortalSession,
  stripePremiumWebhook,
  onAuthUserDeletedCancelStripe,
} = require("./premium/stripe_billing");
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
exports.getPremiumBillingContext = getPremiumBillingContext;
exports.createPremiumCheckoutSession = createPremiumCheckoutSession;
exports.createPremiumPortalSession = createPremiumPortalSession;
exports.stripePremiumWebhook = stripePremiumWebhook;
exports.onAuthUserDeletedCancelStripe = onAuthUserDeletedCancelStripe;

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

const stageBFunctions = createStageBFunctions();
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
