// Staff removal (adminDeleteMessage) needs no change for server channel
// photos and videos: its attachment sweep deletes an object only when the
// object's custom metadata binds the exact message path AND author. This
// proves the binding the server media pipeline writes is exactly that one.
const assert = require("node:assert/strict");
const { test } = require("node:test");

const { getApps, initializeApp } = require("firebase-admin/app");
if (getApps().length === 0) {
  initializeApp({
    projectId: "server-message-media-admin-test",
    storageBucket: "yovoice-test.firebasestorage.app",
  });
}

const { attachmentReferences, deleteAttachments } = require("../admin/messages");
const {
  serverMessageMediaStoragePath,
  serverMessageMediaUploadMetadata,
  serverMessagePath,
} = require("../servers/message_media_contract");

const BUCKET = "yovoice-test.firebasestorage.app";
const SERVER = "srv-admin";
const CHANNEL = "general";
const AUTHOR = "author-1";
const MESSAGE = `cm_${"9".repeat(40)}`;

function bucketWith(metadataByPath, deletes) {
  return {
    name: BUCKET,
    file(path) {
      return {
        async getMetadata() {
          return [{ metadata: metadataByPath.get(path) ?? {} }];
        },
        async delete() {
          deletes.push(path);
        },
      };
    },
  };
}

test("a server channel media object bound to its message and author is deleted by staff removal", async () => {
  const path = serverMessageMediaStoragePath({
    serverId: SERVER, channelId: CHANNEL, ownerId: AUTHOR, messageId: MESSAGE, contentType: "image/jpeg",
  });
  const metadata = serverMessageMediaUploadMetadata({
    serverId: SERVER, channelId: CHANNEL, ownerId: AUTHOR, messageId: MESSAGE, type: "image",
  });
  const message = { senderId: AUTHOR, mediaUrl: `gs://${BUCKET}/${path}` };
  const plan = attachmentReferences(message);
  assert.deepEqual(plan.references, [message.mediaUrl]);
  const deletes = [];
  const outcome = await deleteAttachments(plan.references, {
    messagePath: serverMessagePath(SERVER, CHANNEL, MESSAGE),
    authorId: AUTHOR,
    bucket: bucketWith(new Map([[path, metadata]]), deletes),
  });
  assert.deepEqual(outcome, [{ deleted: true }]);
  assert.deepEqual(deletes, [path]);
});

test("a mismatched binding (another message or another author) is never deleted", async () => {
  const path = serverMessageMediaStoragePath({
    serverId: SERVER, channelId: CHANNEL, ownerId: AUTHOR, messageId: MESSAGE, contentType: "video/mp4",
  });
  const metadata = serverMessageMediaUploadMetadata({
    serverId: SERVER, channelId: CHANNEL, ownerId: AUTHOR, messageId: MESSAGE, type: "video",
  });
  const deletes = [];
  const bucket = bucketWith(new Map([[path, metadata]]), deletes);
  const reference = `gs://${BUCKET}/${path}`;
  const otherMessage = await deleteAttachments([reference], {
    messagePath: serverMessagePath(SERVER, CHANNEL, `cm_${"8".repeat(40)}`),
    authorId: AUTHOR,
    bucket,
  });
  const otherAuthor = await deleteAttachments([reference], {
    messagePath: serverMessagePath(SERVER, CHANNEL, MESSAGE),
    authorId: "someone-else",
    bucket,
  });
  assert.deepEqual(otherMessage, [{ deleted: false, reason: "ownership-mismatch" }]);
  assert.deepEqual(otherAuthor, [{ deleted: false, reason: "ownership-mismatch" }]);
  assert.deepEqual(deletes, []);
});
