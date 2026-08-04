const { initializeApp } = require("firebase-admin/app");

initializeApp();

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

const { getMutualFriends, getFriendSuggestions } = require("./friends/social_graph");

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
