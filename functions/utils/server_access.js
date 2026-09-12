const { fail } = require("../integrity/guards");

const SERVER_MARKERS = ["serverSchemaVersion", "serverType", "serverActivationState"];
const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/u;

// A malformed or future version is still a versioned boundary. Never treat
// `version !== 1` as permission to fall back to legacy Club authority.
function isVersionedServer(data) {
  return Boolean(data && SERVER_MARKERS.some((key) => Object.hasOwn(data, key)));
}

function denyLegacyServerAccess() {
  fail("permission-denied", "This server resource requires its versioned access flow.");
}

function assertLegacyClubData(data) {
  if (isVersionedServer(data)) denyLegacyServerAccess();
}

async function readDocument(db, transaction, path) {
  const reference = db.doc(path);
  return transaction ? transaction.get(reference) : reference.get();
}

// Legacy room tokens/control/media use roomId as the RTC namespace and do
// not bind a channel/session/revision. They cannot safely serve V1 anchors,
// including a legacy room whose parent Club was upgraded in place.
async function assertLegacyRoomAccess({ db, transaction = null, roomId, room = null }) {
  const data = room ?? (await readDocument(db, transaction, `rooms/${roomId}`)).data();
  if (!data) return;
  if (Object.hasOwn(data, "serverSchemaVersion") || Object.hasOwn(data, "serverId")) {
    denyLegacyServerAccess();
  }
  const clubId = data.clubId;
  if (typeof clubId === "string" && clubId.length > 0) {
    if (!SAFE_ID.test(clubId)) denyLegacyServerAccess();
    const club = await readDocument(db, transaction, `clubs/${clubId}`);
    assertLegacyClubData(club.exists ? club.data() : null);
  }
}

// Reuse the ONE canonical V1 policy evaluator for legacy callable names.
// Kept lazy so legacy-only cold starts do not load the server domain.
async function assertServerChannelAccessIfVersioned({
  db, transaction = null, uid, serverId, channelId, capability = "read",
  clubSnapshot = null,
}) {
  const check = async (currentTransaction) => {
    const club = clubSnapshot ?? await readDocument(db, currentTransaction, `clubs/${serverId}`);
    if (!isVersionedServer(club.exists ? club.data() : null)) return null;
    const { readChannelAccess } = require("../servers/authority");
    return readChannelAccess({ db, transaction: currentTransaction, uid, serverId, channelId, capability });
  };
  return transaction ? check(transaction) : db.runTransaction(check);
}

module.exports = {
  assertLegacyClubData, assertLegacyRoomAccess,
  assertServerChannelAccessIfVersioned, isVersionedServer,
};
