const { fail, requireId, transactionGetAll } = require("../integrity/guards");
const {
  MAX_SERVER_CHANNELS, MEDIA_KINDS, canonicalChannelId, canonicalServerId, creationInput,
} = require("./contract");
const { canonicalMember, canonicalServer, denied } = require("./authority");
const {
  hasFamilyServerCapacity, readOwnerAllocations, requireFreeServerCapacity, writeCapacityGuards,
} = require("./capacity");
const { createServerOperations } = require("./operations");
const { templateChannels } = require("./templates");
const {
  canonicalDisplayName, channelDocument, channelRoomDocument,
  memberDocument, membershipMirror, writeChannelGrant,
} = require("./documents");

function createServerCreationService(dependencies) {
  const { db } = dependencies;
  const operations = createServerOperations(dependencies);

  async function createServerV1(request) {
    const input = creationInput(request.data);
    return operations.execute(request, "server.create.v1", input, async ({
      transaction, auth, profile, prior, now,
    }) => {
      const family = input.serverType === "family";
      const reservationReference = family
        ? db.doc(`serverFamilyOwnerReservations/${auth.uid}`) : null;
      const reservation = reservationReference ? await transaction.get(reservationReference) : null;
      const reserved = reservation?.exists ? reservation.data() : null;
      if (reserved && (reserved.schemaVersion !== 1 || reserved.ownerId !== auth.uid ||
          reserved.status !== "active")) fail("data-loss", "The family ownership reservation needs reconciliation.");
      const serverId = reserved
        ? requireId(reserved.serverId, "reserved family server id")
        : canonicalServerId(auth.uid, input.requestId, input.serverType);
      if (prior && prior.serverId !== serverId) denied();
      const reference = db.doc(`clubs/${serverId}`);
      const [existing, membership] = await transactionGetAll(
        transaction, reference, reference.collection("members").doc(auth.uid),
      );
      if (existing.exists) {
        const server = existing.data();
        if (server.ownerId !== auth.uid || server.deletionInProgress === true) denied();
        if (server.serverSchemaVersion !== undefined) {
          canonicalServer(existing, { allowHeld: true });
          canonicalMember(membership, auth.uid, server);
          if (server.serverType !== input.serverType) denied();
        } else if (!family || server.type !== "family" || server.status !== "active" ||
            server.privacy !== "inviteOnly" || !membership.exists ||
            membership.data()?.userId !== auth.uid || membership.data()?.role !== "owner" ||
            membership.data()?.banned === true) denied();
        if (prior) return { ...prior, alreadyExisted: true };
        if (!family) fail("data-loss", "A server exists without its creation receipt.");
        const channels = await transaction.get(reference.collection("channels").limit(MAX_SERVER_CHANNELS + 1));
        if (channels.size > MAX_SERVER_CHANNELS || !channels.docs.some((doc) => doc.id === server.defaultVoiceChannelId)) {
          fail("failed-precondition", "The existing family server requires reconciliation.");
        }
        // Recovery never renames or repairs the protected legacy family graph.
        if (!reserved) transaction.create(reservationReference, {
          schemaVersion: 1, ownerId: auth.uid, serverId, status: "active", updatedAt: now,
        });
        return {
          serverId, defaultChannelId: server.defaultVoiceChannelId,
          channelIds: channels.docs.map((doc) => doc.id), alreadyExisted: true,
        };
      }
      if (prior || reserved) fail("data-loss", "The reserved server graph is unavailable.");
      // A family is charged to its own one-per-owner policy, never to the free
      // allowance. The deterministic root alone cannot enforce ownership after
      // transfer, so the shared accounting's bounded canonical family count
      // also protects pre-reservation family data.
      const capacity = await readOwnerAllocations({ db, transaction, uid: auth.uid });
      if (family) {
        if (!hasFamilyServerCapacity(capacity)) fail("failed-precondition", "Your existing family server must be recovered first.");
      } else {
        requireFreeServerCapacity(capacity);
      }
      const seeds = templateChannels(input.serverType, input.defaultLanguage, input.templateVersion);
      const ids = seeds.map((seed) => canonicalChannelId(serverId, seed.seedKey));
      const voiceIndex = seeds.findIndex((seed) => MEDIA_KINDS.includes(seed.kind));
      const chatIndex = seeds.findIndex((seed) => seed.kind === "text");
      const announcementIndex = seeds.findIndex((seed) => seed.kind === "announcements");
      const loungeRoomId = requireId(`club_lounge_${serverId}`, "loungeRoomId");
      const server = {
        serverSchemaVersion: 1, serverType: input.serverType, templateVersion: input.templateVersion,
        entitlementPolicyId: family ? "familyFreeV1" : "freeServersV1",
        serverActivationState: "held", revision: 1,
        name: input.name, description: input.description, ownerId: auth.uid,
        ownerName: canonicalDisplayName(profile), avatarUrl: null, bannerUrl: null,
        privacy: input.privacy, type: family ? "family" : "community", status: "preparing",
        defaultLanguage: input.defaultLanguage, memberCount: 1, onlineCount: 0,
        defaultChatChannelId: ids[chatIndex], defaultVoiceChannelId: ids[voiceIndex], loungeRoomId,
        announcementChannelId: announcementIndex === -1 ? null : ids[announcementIndex],
        createdAt: now, updatedAt: now,
      };
      const owner = memberDocument(auth.uid, profile, "owner", now);
      const channels = seeds.map((seed, index) => channelDocument({
        serverId, channelId: ids[index], input: seed, uid: auth.uid, position: index, now,
        roomId: index === voiceIndex ? loungeRoomId : null,
      }));
      // Even child collisions fail before writing rather than adopting arbitrary
      // pre-existing content into the server. This transaction is the whole seed.
      const targets = [db.doc(`users/${auth.uid}/clubs/${serverId}`),
        ...ids.map((id) => reference.collection("channels").doc(id)),
        ...channels.filter((channel) => channel.roomId).map((channel) => db.doc(`rooms/${channel.roomId}`))];
      const collisions = await transactionGetAll(transaction, ...targets);
      if (membership.exists || collisions.some((snapshot) => snapshot.exists)) {
        fail("data-loss", "An incomplete server graph needs reconciliation.");
      }
      transaction.create(reference, server);
      transaction.create(reference.collection("members").doc(auth.uid), owner);
      transaction.create(reference.collection("memberAuthorizations").doc(auth.uid), {
        schemaVersion: 1, userId: auth.uid, revision: 1, status: "member", updatedAt: now,
      });
      transaction.create(db.doc(`users/${auth.uid}/clubs/${serverId}`), membershipMirror(serverId, server, owner));
      channels.forEach((channel, index) => {
        const channelId = ids[index];
        transaction.create(reference.collection("channels").doc(channelId), channel);
        if (channel.roomId) transaction.create(db.doc(`rooms/${channel.roomId}`), channelRoomDocument({
          serverId, channelId, server, channel, now,
        }));
        if (channel.accessMode === "restricted") writeChannelGrant({
          db, transaction, serverId, channelId, channel, member: owner, now,
        });
      });
      if (family) transaction.create(reservationReference, {
        schemaVersion: 1, ownerId: auth.uid, serverId, status: "active", updatedAt: now,
      });
      writeCapacityGuards(transaction, capacity, auth.uid, now);
      return { serverId, defaultChannelId: ids[voiceIndex], channelIds: ids, alreadyExisted: false };
    }, { creation: true });
  }

  return { createServerV1 };
}

module.exports = { createServerCreationService };
