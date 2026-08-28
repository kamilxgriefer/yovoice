const { onCall } = require("firebase-functions/v2/https");

const { requireProtectedOwner } = require("../utils/auth");

const { db } = require("../utils/firestore");
const { listLiveActiveRoomDocs } = require("../rooms/live_rooms");

const REGION = "europe-west1";

async function loadAdminDashboardStats({
  firestore = db,
  listLiveRooms = listLiveActiveRoomDocs,
} = {}) {
  const [users, rooms, clubs, liveRooms] = await Promise.all([
    firestore.collection("users").count().get(),
    firestore.collection("rooms").count().get(),
    firestore.collection("clubs").count().get(),
    listLiveRooms({ surface: "getAdminDashboard" }),
  ]);

  return {
    users: users.data().count,
    rooms: rooms.data().count,
    clubs: clubs.data().count,
    liveRooms: liveRooms.docs.length,
  };
}

const getAdminDashboard = onCall(
  {
    region: REGION,
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
    enforceAppCheck: false,
  },
  async (request) => {
    await requireProtectedOwner(request);
    // NOT a `.count()` on `status == "active" && isLive == true`: that
    // form drops every room with no `status` field, which is 25 of the 45
    // in production. See functions/rooms/live_rooms.js.
    return loadAdminDashboardStats();
  },
);

module.exports = {
  getAdminDashboard,
  loadAdminDashboardStats,
};
