const { fail } = require("../integrity/guards");

const ROOM_TYPES = new Set(["community", "temporary"]);

function validatedGuardRoomIds(snapshot, uid, maxActiveRooms) {
  if (!snapshot?.exists) return null;
  const data = snapshot.data() ?? {};
  const ids = data.activeRoomIds;
  if (
    ![1, 2].includes(data.schemaVersion) ||
    data.ownerId !== uid ||
    !Array.isArray(ids) ||
    ids.length > maxActiveRooms ||
    new Set(ids).size !== ids.length ||
    ids.some((id) =>
      typeof id !== "string" || !/^[A-Za-z0-9_-]{1,160}$/u.test(id))
  ) {
    fail("data-loss", "The room-capacity guard is malformed.");
  }
  if (
    data.schemaVersion === 2 &&
    typeof data.capacityLocked !== "boolean"
  ) {
    fail("data-loss", "The room-capacity guard is malformed.");
  }
  return {
    activeRoomIds: ids,
    capacityLocked: data.schemaVersion === 2 && data.capacityLocked === true,
  };
}

function isActiveOrdinaryRoom(snapshot, uid) {
  if (!snapshot?.exists) return false;
  const room = snapshot.data() ?? {};
  return room.hostId === uid &&
    room.status === "active" &&
    !room.clubId &&
    room.roomKind !== "clubLounge" &&
    ROOM_TYPES.has(room.roomType);
}

function boundedLegacyRoomQuery(db, uid, maxActiveRooms) {
  return db.collection("rooms")
    .where("hostId", "==", uid)
    .where("status", "==", "active")
    .limit(maxActiveRooms + 1);
}

module.exports = {
  ROOM_TYPES,
  boundedLegacyRoomQuery,
  isActiveOrdinaryRoom,
  validatedGuardRoomIds,
};
