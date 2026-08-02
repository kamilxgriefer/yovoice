const { onCall } = require("firebase-functions/v2/https");

const { requireAdminCenterAccess } = require("../utils/auth");

const { db } = require("../utils/firestore");

const REGION = "europe-west1";

const getAdminDashboard = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
  },
  async (request) => {
    requireAdminCenterAccess(request);

    const [users, rooms, clubs, activeRooms] = await Promise.all([
      db.collection("users").count().get(),

      db.collection("rooms").count().get(),

      db.collection("clubs").count().get(),

      db
        .collection("rooms")
        .where("status", "==", "active")
        .where("isLive", "==", true)
        .count()
        .get(),
    ]);

    return {
      users: users.data().count,
      rooms: rooms.data().count,
      clubs: clubs.data().count,
      liveRooms: activeRooms.data().count,
    };
  },
);

module.exports = {
  getAdminDashboard,
};
