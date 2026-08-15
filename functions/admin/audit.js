const { onCall, HttpsError } = require("firebase-functions/v2/https");

const { requireAdminCenterAccess } = require("../utils/auth");

const {
  db,
  normalizeText,
  positiveInteger,
  timestampToIso,
} = require("../utils/firestore");

const REGION = "europe-west1";

function mapAuditLog(document) {
  const data = document.data() ?? {};

  // writeAuditLog stores a FLAT document (actorId/actorRole/targetType/
  // targetId/targetLabel); the nested reads below it are kept only for
  // any historical row written before that shape existed.
  return {
    id: document.id,

    category: data.category ?? "general",
    action: data.action ?? "unknown",

    actor: {
      uid: data.actorId ?? data.actor?.uid ?? null,
      email: data.actorEmail ?? data.actor?.email ?? null,
      role: data.actorRole ?? data.actor?.role ?? null,
    },

    target: {
      type: data.targetType ?? data.target?.type ?? null,
      id: data.targetId ?? data.target?.id ?? null,
      name: data.targetLabel ?? data.target?.name ?? null,
      email: data.target?.email ?? null,
    },

    details:
      typeof data.details === "object" && data.details !== null
        ? data.details
        : {},

    createdAt: timestampToIso(data.createdAt),
  };
}

function matchesSearch(log, search) {
  if (!search) {
    return true;
  }

  const searchable = [
    log.id,
    log.category,
    log.action,
    log.actor.uid,
    log.actor.email,
    log.actor.role,
    log.target.type,
    log.target.id,
    log.target.name,
    log.target.email,
    JSON.stringify(log.details),
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  return searchable.includes(search);
}

const listAdminAuditLogs = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    requireAdminCenterAccess(request);

    const limit = positiveInteger(request.data?.limit, 50, 100);

    const search = normalizeText(request.data?.search, 160).toLowerCase();

    const category = normalizeText(request.data?.category, 60);

    const action = normalizeText(request.data?.action, 120);

    const actorUid = normalizeText(request.data?.actorUid, 128);

    const targetId = normalizeText(request.data?.targetId, 128);

    const cursorId = normalizeText(request.data?.cursorId, 128);

    let query = db
      .collection("adminAuditLogs")
      .orderBy("createdAt", "desc")
      .limit(limit);

    if (category) {
      query = db
        .collection("adminAuditLogs")
        .where("category", "==", category)
        .orderBy("createdAt", "desc")
        .limit(limit);
    } else if (action) {
      query = db
        .collection("adminAuditLogs")
        .where("action", "==", action)
        .orderBy("createdAt", "desc")
        .limit(limit);
    } else if (actorUid) {
      query = db
        .collection("adminAuditLogs")
        .where("actorId", "==", actorUid)
        .orderBy("createdAt", "desc")
        .limit(limit);
    } else if (targetId) {
      query = db
        .collection("adminAuditLogs")
        .where("targetId", "==", targetId)
        .orderBy("createdAt", "desc")
        .limit(limit);
    }

    if (cursorId) {
      const cursorSnapshot = await db
        .collection("adminAuditLogs")
        .doc(cursorId)
        .get();

      if (cursorSnapshot.exists) {
        query = query.startAfter(cursorSnapshot);
      }
    }

    const snapshot = await query.get();

    const logs = snapshot.docs
      .map(mapAuditLog)
      .filter((log) => matchesSearch(log, search));

    const lastDocument =
      snapshot.docs.length > 0 ? snapshot.docs[snapshot.docs.length - 1] : null;

    return {
      logs,
      nextCursorId:
        snapshot.docs.length === limit && lastDocument ? lastDocument.id : null,
    };
  },
);

const getAdminAuditLog = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    requireAdminCenterAccess(request);

    const logId = normalizeText(request.data?.logId, 128);

    if (!logId) {
      throw new HttpsError("invalid-argument", "An audit log id is required.");
    }

    const snapshot = await db.collection("adminAuditLogs").doc(logId).get();

    if (!snapshot.exists) {
      throw new HttpsError(
        "not-found",
        "The selected audit log was not found.",
      );
    }

    return {
      log: mapAuditLog(snapshot),
    };
  },
);

const getAuditLogFilters = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    requireAdminCenterAccess(request);

    const snapshot = await db
      .collection("adminAuditLogs")
      .orderBy("createdAt", "desc")
      .limit(500)
      .get();

    const categories = new Set();
    const actions = new Set();

    for (const document of snapshot.docs) {
      const data = document.data() ?? {};

      if (data.category) {
        categories.add(data.category);
      }

      if (data.action) {
        actions.add(data.action);
      }
    }

    return {
      categories: Array.from(categories).sort(),

      actions: Array.from(actions).sort(),
    };
  },
);

module.exports = {
  listAdminAuditLogs,
  getAdminAuditLog,
  getAuditLogFilters,
};
