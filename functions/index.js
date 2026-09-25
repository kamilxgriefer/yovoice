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
  onServerInviteWritten,
  sweepExpiredServerInvitesSchedule,
} = require("./notifications/invites");
// Comments and @mentions on Voice Moments and Yeels, and the Server event
// reminders the app has accepted opt-ins for since Servers V1 (ADR-213).
const {
  onMomentCommentCreated,
  onMomentCommentDeleted,
  onReelCommentCreated,
  onReelCommentDeleted,
} = require("./notifications/engagement");
const {
  sendServerEventRemindersSchedule,
} = require("./notifications/server_events");

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
exports.onServerInviteWritten = onServerInviteWritten;
exports.sweepExpiredServerInvitesSchedule = sweepExpiredServerInvitesSchedule;
exports.onMomentCommentCreated = onMomentCommentCreated;
exports.onMomentCommentDeleted = onMomentCommentDeleted;
exports.onReelCommentCreated = onReelCommentCreated;
exports.onReelCommentDeleted = onReelCommentDeleted;
exports.sendServerEventRemindersSchedule = sendServerEventRemindersSchedule;

/*
|--------------------------------------------------------------------------
| Account sessions
|--------------------------------------------------------------------------
*/

const {
  revokeMyRefreshTokens,
} = require("./auth/session_management");

exports.revokeMyRefreshTokens = revokeMyRefreshTokens;

// Pre-registered account takeover, Phase 1: one remediation authority, two
// triggers (the owner's own client right after a returning Google/Apple
// sign-in, and a bounded sweeper), plus the Auth onCreate trigger that
// records an unverified password while it is still visible. See
// functions/auth/federated_takeover.js and docs/SECURITY.md.
const {
  onAuthUserCreated,
  secureFederatedSignInV1,
  sweepFederatedTakeoverSchedule,
} = require("./auth/federated_takeover");

exports.onAuthUserCreated = onAuthUserCreated;
exports.secureFederatedSignInV1 = secureFederatedSignInV1;
exports.sweepFederatedTakeoverSchedule = sweepFederatedTakeoverSchedule;

/*
|--------------------------------------------------------------------------
| Account deletion (ADR-206)
|--------------------------------------------------------------------------
| One leased pipeline with two entry points. `deleteAccountSelfV1` marks intent
| and returns; the outbox worker performs the bounded teardown and ends with
| admin.auth().deleteUser(). The existing onAuthUserDeleted trigger above is
| both the pipeline's last step and its second entry point, so a console or
| staff deletion gets the same teardown instead of leaving an e-mail behind.
|
| The callable is fail-closed behind appConfig/accountDeletion: a MISSING
| document means disabled. Deploy the worker and the trigger first, exercise
| one real account, then write { enabled: true } — see docs/DEPLOYMENT.md.
*/

const {
  deleteAccountSelfV1,
  onAccountDeletionOutboxCreated,
  processAccountDeletionOutboxSchedule,
} = require("./account/deletion");

exports.deleteAccountSelfV1 = deleteAccountSelfV1;
exports.onAccountDeletionOutboxCreated = onAccountDeletionOutboxCreated;
exports.processAccountDeletionOutboxSchedule =
  processAccountDeletionOutboxSchedule;

/*
|--------------------------------------------------------------------------
| Profile
|--------------------------------------------------------------------------
*/

const { onProfileIdentityChanged } = require("./profile/fanout");
const { updateMyDisplayName } = require("./profile/display_name");
const { setMyProfileVisibility } = require("./profile/profile_visibility");
const {
  confirmCreatorAdultEligibility,
  onAuthUserDeleted,
  onUserPrivacySourceChanged,
  searchPublicProfiles,
  setCreatorAudienceEnabled,
} = require("./profile/public_profiles");

exports.onProfileIdentityChanged = onProfileIdentityChanged;
exports.confirmCreatorAdultEligibility = confirmCreatorAdultEligibility;
exports.updateMyDisplayName = updateMyDisplayName;
exports.setMyProfileVisibility = setMyProfileVisibility;
exports.onAuthUserDeleted = onAuthUserDeleted;
exports.onUserPrivacySourceChanged = onUserPrivacySourceChanged;
exports.searchPublicProfiles = searchPublicProfiles;
exports.setCreatorAudienceEnabled = setCreatorAudienceEnabled;

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
  createStageBIntegrityRuntime,
} = require("./integrity/stage_b_runtime");
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
  // Clients activate App Check, but platform attestation is not yet healthy
  // (Android tokens fail to decode, iOS lacks the App Attest entitlement and
  // web has no reCAPTCHA site key). Enforcement must not be enabled before
  // console telemetry shows verified traffic on iOS, Android and Web.
  enforceAppCheck: strictBooleanEnvironment(
    "YOVOICE_ENFORCE_REELS_APP_CHECK",
  ),
}));

// GIFs in the composer (ADR-167). Firebase CLI discovers the export map before
// it loads functions/.env, so an environment-controlled registration silently
// omitted searchGifs/reportGifAsset from a real deploy. The bundled provider is
// therefore selected in source and all three endpoints are static. Firestore's
// appConfig/gif switch remains the immediate, fail-closed operational control.
const { createGifFunctions } = require("./media/gif/catalog");
const { GIF_PROVIDERS } = require("./media/gif/gif_ref");
const deployedGifProvider = GIF_PROVIDERS.yovoice;
// GIPHY, option B (ADR-214). Search and trending run in the CLIENT, as GIPHY's
// API terms require; the server stays the send-time authority. `resolveGif`
// fetches one chosen GIPHY id with the GIPHY_API_KEY secret, applies the
// rating/denylist/block filter and writes the `gifAssets` record the message
// transaction reads. It is SOURCE-GATED OFF: turning it on declares the
// GIPHY_API_KEY secret and adds an export, so it needs the secret set first,
// the pinned export list in test/cold_start_module_graph.test.js and the
// secret-discovery expectation updated in the same reviewed commit, and one
// deploy wave with the catalog. While it is off, getGifCatalog advertises no
// resolvable provider, so a client built with a GIPHY key still shows
// Originals only.
const GIPHY_SEND_RESOLVE_ENABLED = false;
// Every send path accepts BOTH providers. A GIPHY reference can only resolve
// once `resolveGif` has written its server-owned record, so accepting it here
// ahead of the resolver is inert, and it removes the split-revision hazard
// where Originals (and every Originals recent) stop sending on a provider flip.
const gifSendProviders = Object.freeze([
  GIF_PROVIDERS.yovoice,
  GIF_PROVIDERS.giphy,
]);
Object.assign(exports, createGifFunctions({
  providerName: deployedGifProvider,
  resolveProviders: GIPHY_SEND_RESOLVE_ENABLED ? [GIF_PROVIDERS.giphy] : [],
  // Telemetry first: App Check is activated in clients but attestation is not
  // yet healthy on every platform, so enforcement stays off until console
  // metrics show verified traffic on Android, iOS and Web (ADR-214).
  enforceAppCheck: strictBooleanEnvironment(
    "YOVOICE_ENFORCE_GIF_APP_CHECK",
  ),
}));

const stageBFunctions = createStageBFunctions({
  // Message publication uses a source-owned allow-set (ADR-214) rather than a
  // missing env value, so a selectable Originals or GIPHY result always has a
  // send path that accepts its provider.
  runtime: createStageBIntegrityRuntime({
    directOptions: {
      gifProviderName: deployedGifProvider,
      gifProviderNames: gifSendProviders,
    },
    communityOptions: {
      gifProviderName: deployedGifProvider,
      gifProviderNames: gifSendProviders,
    },
  }),
  // Rollout switch: clients activate App Check, but production enforcement
  // must only flip after Android/iOS/Web attestation telemetry is healthy. Invalid configuration fails the deployment instead of
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
| Servers V1 — static registration, runtime activation
|--------------------------------------------------------------------------
| Firebase discovers exports before it loads functions/.env, so an environment
| variable cannot safely decide which function names exist. The base fifty-five
| Servers exports are always discoverable and can therefore be deployed by the
| reviewed phase selectors. Every callable then reads the server-owned
| appConfig/serversV1 document and fails closed until an operator enables its
| exact account cohort. Workers have a separate runtime bit so rollout can hold
| them before activation and keep them draining during rollback. Podcast Egress
| remains source-disabled: none of its seven exports, service construction or
| missing credential is part of this registration.
*/
const {
  createServerMessageFunctions,
  createServersV1Functions,
} = require("./servers/registration");
Object.assign(exports, createServersV1Functions({
  // App Check remains in telemetry mode for this first internal rollout. A
  // later source-reviewed revision may set it true after platform telemetry.
  enforceAppCheck: false,
  // A later source-reviewed revision may register the seven Egress exports
  // only after its dedicated credential exists and the provider drill passes.
  enablePodcastRecording: false,
}));
// Server channel messaging parity with direct messages: emoji reactions and
// photo/video messages. A separate, explicitly listed extension
// (SERVER_MESSAGE_EXPORT_NAMES) behind the same appConfig/serversV1 gate; the
// frozen base manifest above is unchanged.
Object.assign(exports, createServerMessageFunctions({ enforceAppCheck: false }));

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
