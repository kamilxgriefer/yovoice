// Community server follows. Membership remains the access authority; this
// preference only records whether the current member wants creator-style
// updates from a community server.

const {
  fail,
  requireBoolean,
  requireExactInput,
  requireId,
  requireRequestId,
} = require("../integrity/guards");
const { denied, readServerAccess } = require("./authority");
const { createServerOperations } = require("./operations");

function canonicalFollow(snapshot, { serverId, uid }) {
  if (!snapshot.exists) return null;
  const value = snapshot.data() ?? {};
  const keys = Object.keys(value).sort();
  const expectedKeys = [
    "createdAt", "following", "schemaVersion", "serverId", "updatedAt", "userId",
  ];
  if (keys.length !== expectedKeys.length ||
      keys.some((key, index) => key !== expectedKeys[index]) ||
      value.schemaVersion !== 1 || value.serverId !== serverId ||
      value.userId !== uid || value.following !== true ||
      typeof value.createdAt?.toMillis !== "function" ||
      typeof value.updatedAt?.toMillis !== "function") {
    fail("data-loss", "The server follow preference needs reconciliation.");
  }
  return value;
}

function matchingProjections(primary, mirror) {
  if (primary === null || mirror === null) return primary === mirror;
  return primary.schemaVersion === mirror.schemaVersion &&
    primary.serverId === mirror.serverId && primary.userId === mirror.userId &&
    primary.following === mirror.following &&
    primary.createdAt.toMillis() === mirror.createdAt.toMillis() &&
    primary.updatedAt.toMillis() === mirror.updatedAt.toMillis();
}

function createServerFollowService(dependencies) {
  const { db } = dependencies;
  if (!db?.runTransaction) throw new TypeError("db is required.");
  const operations = createServerOperations(dependencies);

  async function setCommunityServerFollowV1(request) {
    requireExactInput(
      request.data,
      ["serverId", "requestId", "following"],
      ["serverId", "requestId", "following"],
    );
    const input = {
      serverId: requireId(request.data.serverId, "serverId"),
      requestId: requireRequestId(request.data.requestId),
      following: requireBoolean(request.data.following, "following"),
    };
    return operations.execute(
      request,
      "server.community.follow.set.v1",
      input,
      async ({ transaction, auth, prior, now }) => {
        const access = await readServerAccess({
          db,
          transaction,
          uid: auth.uid,
          serverId: input.serverId,
        });
        if (access.server.serverType !== "community") denied();

        const reference = access.reference.collection("followers").doc(auth.uid);
        const mirrorReference = db.doc(
          `users/${auth.uid}/serverFollows/${input.serverId}`,
        );
        const [snapshot, mirrorSnapshot] = await Promise.all([
          transaction.get(reference),
          transaction.get(mirrorReference),
        ]);
        const stored = canonicalFollow(snapshot, {
          serverId: input.serverId,
          uid: auth.uid,
        });
        const mirrored = canonicalFollow(mirrorSnapshot, {
          serverId: input.serverId,
          uid: auth.uid,
        });
        if (!matchingProjections(stored, mirrored)) {
          fail("data-loss", "The server follow projections need reconciliation.");
        }

        if (prior) {
          if ((stored !== null) === prior.following) return prior;
          fail("aborted", "The follow preference changed after this request.");
        }

        if (input.following) {
          const value = {
            schemaVersion: 1,
            serverId: input.serverId,
            userId: auth.uid,
            following: true,
            createdAt: stored?.createdAt ?? now,
            updatedAt: now,
          };
          transaction.set(reference, value);
          transaction.set(mirrorReference, value);
        } else {
          transaction.delete(reference);
          if (mirrorSnapshot.exists) transaction.delete(mirrorReference);
        }

        return {
          serverId: input.serverId,
          following: input.following,
          changed: input.following ? stored === null : stored !== null,
        };
      },
    );
  }

  return { setCommunityServerFollowV1 };
}

module.exports = { createServerFollowService };
