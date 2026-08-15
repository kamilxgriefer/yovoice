// getStaffOverview — the Staff Center's opening screen, in one call.
//
// Every number is a real aggregate over authoritative collections and
// every list is a real query; nothing here is a placeholder counter.
// PROTECTED-OWNER-ONLY, like directory search: the overview names user
// totals, staff composition and security alerts, which are ownership
// facts. Moderation tiers keep their own surfaces (the reports queue)
// with their own gates.
//
// Summaries deliberately carry ids and roles but NO emails — the spec
// for general summaries. The full audit browser is a separate,
// owner-gated call.

const { onCall } = require("firebase-functions/v2/https");

const { requireProtectedOwner } = require("../utils/auth");
const { db, timestampToIso } = require("../utils/firestore");

const LIST_LIMIT = 5;

const SANCTION_ACTIONS = [
  "warn_user",
  "communication_mute",
  "lift_communication_mute",
  "ban_user",
  "unban_user",
];

const ROLE_CHANGE_ACTIONS = ["assign_user_role", "bootstrap_super_admin"];

const SECURITY_ALERT_ACTION = "security_alert_non_owner_super_admin";

/// Flat audit schema (writeAuditLog), summarised WITHOUT the actor/
/// target email fields.
function summariseAuditRow(document) {
  const data = document.data() ?? {};
  return {
    id: document.id,
    action: String(data.action ?? "unknown"),
    actorId: data.actorId ?? null,
    actorRole: data.actorRole ?? null,
    targetType: data.targetType ?? null,
    targetId: data.targetId ?? null,
    details: typeof data.details === "object" && data.details !== null
      ? {
          reason: data.details.reason ?? null,
          role: data.details.role ?? data.details.newRole ?? null,
          previousRole: data.details.previousRole ?? null,
          durationHours: data.details.durationHours ?? null,
          expiresAt: data.details.expiresAt ?? null,
          attempted: data.details.attempted ?? null,
        }
      : {},
    createdAt: timestampToIso(data.createdAt),
  };
}

function summariseReportRow(document) {
  const data = document.data() ?? {};
  return {
    id: document.id,
    targetType: data.targetType ?? null,
    reason: data.reason ?? null,
    status: data.status ?? "open",
    reporterId: data.reporterId ?? null,
    reportedUserId: data.reportedUserId ?? null,
    createdAt: timestampToIso(data.createdAt),
  };
}

function summariseRoomRow(document) {
  const data = document.data() ?? {};
  return {
    id: document.id,
    name: data.name ?? "",
    experience: data.experience ?? null,
    hostId: data.hostId ?? null,
    hostName: data.hostName ?? "",
    participantCount: Number(data.participantCount ?? 0),
    createdAt: timestampToIso(data.createdAt),
  };
}

const getStaffOverview = onCall(
  {
    region: "europe-west1",
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
    enforceAppCheck: false,
  },
  async (request) => {
    await requireProtectedOwner(request);

    const audit = db.collection("adminAuditLogs");
    const now = new Date();

    const [
      totalUsers,
      activeRooms,
      openReports,
      indefiniteRestrictions,
      runningRestrictions,
      staffMembers,
      vipUsers,
      securityAlerts,
      latestOpenReportDocs,
      activeRoomDocs,
      recentSanctionDocs,
      recentRoleChangeDocs,
      securityAlertDocs,
    ] = await Promise.all([
      // Auth-authoritative account count via the directory mirror.
      db.collection("userDirectory").count().get(),
      db
        .collection("rooms")
        .where("status", "==", "active")
        .where("isLive", "==", true)
        .count()
        .get(),
      // Non-terminal reports. (A pre-`status` report counts as open in
      // the workflow but is invisible to this filter; none remain in
      // production.)
      db
        .collection("reports")
        .where("status", "in", ["open", "inReview"])
        .count()
        .get(),
      // Active restrictions = never-expiring + not-yet-expired.
      db.collection("restrictions").where("expiresAt", "==", null).count().get(),
      db.collection("restrictions").where("expiresAt", ">", now).count().get(),
      db.collection("userDirectory").where("isStaff", "==", true).count().get(),
      db.collection("userDirectory").where("isVip", "==", true).count().get(),
      audit.where("action", "==", SECURITY_ALERT_ACTION).count().get(),
      db
        .collection("reports")
        .where("status", "==", "open")
        .orderBy("createdAt", "desc")
        .limit(LIST_LIMIT)
        .get(),
      db
        .collection("rooms")
        .where("status", "==", "active")
        .where("isLive", "==", true)
        .limit(LIST_LIMIT)
        .get(),
      audit
        .where("action", "in", SANCTION_ACTIONS)
        .orderBy("createdAt", "desc")
        .limit(LIST_LIMIT)
        .get(),
      audit
        .where("action", "in", ROLE_CHANGE_ACTIONS)
        .orderBy("createdAt", "desc")
        .limit(LIST_LIMIT)
        .get(),
      audit
        .where("action", "==", SECURITY_ALERT_ACTION)
        .orderBy("createdAt", "desc")
        .limit(LIST_LIMIT)
        .get(),
    ]);

    return {
      counts: {
        totalUsers: totalUsers.data().count,
        activeRooms: activeRooms.data().count,
        openReports: openReports.data().count,
        restrictedAccounts:
          indefiniteRestrictions.data().count + runningRestrictions.data().count,
        staffMembers: staffMembers.data().count,
        vipUsers: vipUsers.data().count,
        securityAlerts: securityAlerts.data().count,
      },
      latestOpenReports: latestOpenReportDocs.docs.map(summariseReportRow),
      activeRooms: activeRoomDocs.docs.map(summariseRoomRow),
      recentSanctions: recentSanctionDocs.docs.map(summariseAuditRow),
      recentRoleChanges: recentRoleChangeDocs.docs.map(summariseAuditRow),
      securityAlerts: securityAlertDocs.docs.map(summariseAuditRow),
    };
  },
);

module.exports = { getStaffOverview, SANCTION_ACTIONS, ROLE_CHANGE_ACTIONS };
