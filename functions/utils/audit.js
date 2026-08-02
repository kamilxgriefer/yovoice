const { FieldValue } = require("firebase-admin/firestore");

const { db } = require("./firestore");

function normalizeAuditValue(value) {
  if (value === undefined) {
    return null;
  }

  return value;
}

async function writeAuditLog({
  caller,
  action,
  targetType,
  targetId,
  targetLabel = null,
  details = {},
}) {
  if (!caller?.uid) {
    throw new Error("Audit log requires a valid caller.");
  }

  if (!action) {
    throw new Error("Audit log requires an action.");
  }

  if (!targetType) {
    throw new Error("Audit log requires a target type.");
  }

  if (!targetId) {
    throw new Error("Audit log requires a target id.");
  }

  const normalizedDetails = Object.fromEntries(
    Object.entries(details).map(([key, value]) => [
      key,
      normalizeAuditValue(value),
    ]),
  );

  const auditEntry = {
    actorId: caller.uid,
    actorEmail: caller.token?.email ?? caller.email ?? null,
    actorRole: caller.role ?? caller.token?.role ?? "user",

    action,

    targetType,
    targetId,
    targetLabel,

    details: normalizedDetails,

    createdAt: FieldValue.serverTimestamp(),
  };

  const reference = await db.collection("adminAuditLogs").add(auditEntry);

  return {
    id: reference.id,
    ...auditEntry,
  };
}

async function writeUserAuditLog({
  caller,
  action,
  userId,
  userEmail = null,
  details = {},
}) {
  return writeAuditLog({
    caller,
    action,
    targetType: "user",
    targetId: userId,
    targetLabel: userEmail,
    details,
  });
}

async function writeRoomAuditLog({
  caller,
  action,
  roomId,
  roomName = null,
  details = {},
}) {
  return writeAuditLog({
    caller,
    action,
    targetType: "room",
    targetId: roomId,
    targetLabel: roomName,
    details,
  });
}

async function writeClubAuditLog({
  caller,
  action,
  clubId,
  clubName = null,
  details = {},
}) {
  return writeAuditLog({
    caller,
    action,
    targetType: "club",
    targetId: clubId,
    targetLabel: clubName,
    details,
  });
}

module.exports = {
  writeAuditLog,
  writeUserAuditLog,
  writeRoomAuditLog,
  writeClubAuditLog,
};
