const { onCall } = require("firebase-functions/v2/https");

const { requireProtectedOwner } = require("../utils/auth");

const { db } = require("../utils/firestore");
const { listLiveActiveRoomDocs } = require("../rooms/live_rooms");

const REGION = "europe-west1";

const getAdminDashboard = onCall(
  {
    region: REGION,
    secrets: ["YOVOICE_PROTECTED_OWNER_UID"],
    enforceAppCheck: false,
  },
  async (request) => {
    await requireProtectedOwner(request);

    const [users, rooms, clubs, liveRooms] = await Promise.all([
      db.collection("users").count().get(),

      db.collection("rooms").count().get(),

      db.collection("clubs").count().get(),

      // NOT a `.count()` on `status == "active" && isLive == true`: that
      // form drops every room with no `status` field, which is 25 of the 45
      // in production. See functions/rooms/live_rooms.js.
      listLiveActiveRoomDocs({ surface: "getAdminDashboard" }),
    ]);

    return {
      users: users.data().count,
      rooms: rooms.data().count,
      clubs: clubs.data().count,
      liveRooms: liveRooms.docs.length,
    };
  },
);

module.exports = {
  getAdminDashboard,
};
