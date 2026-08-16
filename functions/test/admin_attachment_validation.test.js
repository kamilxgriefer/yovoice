const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const { getApps, initializeApp } = require("firebase-admin/app");
if (getApps().length === 0) {
  initializeApp({
    projectId: "admin-attachment-test",
    storageBucket: "yovoice-test.firebasestorage.app",
  });
}

const {
  ATTACHMENT_METADATA,
  attachmentReferences,
  deleteAttachments,
  parseStorageObjectReference,
} = require("../admin/messages");

const BUCKET = "yovoice-test.firebasestorage.app";
const MESSAGE_PATH = "conversations/c1/messages/m1";
const OWNER = "user-1";

describe("admin attachment reference validation", () => {
  test("canonical gs and Firebase download references resolve in-bucket", () => {
    assert.deepEqual(
      parseStorageObjectReference(
        `gs://${BUCKET}/message_attachments/user-1/m1/audio.m4a`,
        BUCKET,
      ),
      {
        bucketName: BUCKET,
        objectPath: "message_attachments/user-1/m1/audio.m4a",
      },
    );
    assert.deepEqual(
      parseStorageObjectReference(
        `https://firebasestorage.googleapis.com/v0/b/${BUCKET}` +
          "/o/message_attachments%2Fuser-1%2Fm1%2Fimage.jpg?alt=media",
        BUCKET,
      ),
      {
        bucketName: BUCKET,
        objectPath: "message_attachments/user-1/m1/image.jpg",
      },
    );
  });

  test("foreign buckets, arbitrary hosts, bare paths and traversal are denied",
    () => {
      for (const reference of [
        "gs://other-bucket/users/victim/profile/avatar.jpg",
        "https://example.invalid/v0/b/yovoice-test.firebasestorage.app/o/a",
        "users/victim/profile/avatar.jpg",
        `gs://${BUCKET}/safe/%2e%2e/profile/avatar.jpg`,
        `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/..%2Fsecret`,
        `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/a%252Fb`,
      ]) {
        assert.equal(
          parseStorageObjectReference(reference, BUCKET),
          null,
          `unexpectedly accepted ${reference}`,
        );
      }
    });

  test("a valid path is deleted only when metadata binds exact message and author",
    async () => {
      const deletes = [];
      const metadataByPath = new Map([
        ["message_attachments/user-1/m1/owned.m4a", {
          [ATTACHMENT_METADATA.MESSAGE_PATH]: MESSAGE_PATH,
          [ATTACHMENT_METADATA.OWNER_UID]: OWNER,
        }],
        ["users/victim/profile/avatar.jpg", {}],
      ]);
      const fileCalls = [];
      const bucket = {
        name: BUCKET,
        file(path) {
          fileCalls.push(path);
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

      const outcome = await deleteAttachments([
        `gs://${BUCKET}/message_attachments/user-1/m1/owned.m4a`,
        `gs://${BUCKET}/users/victim/profile/avatar.jpg`,
        "gs://other-bucket/message_attachments/user-1/m1/foreign.m4a",
      ], {
        messagePath: MESSAGE_PATH,
        authorId: OWNER,
        bucket,
      });

      assert.deepEqual(deletes, [
        "message_attachments/user-1/m1/owned.m4a",
      ]);
      assert.deepEqual(fileCalls, [
        "message_attachments/user-1/m1/owned.m4a",
        "users/victim/profile/avatar.jpg",
      ]);
      assert.deepEqual(outcome, [
        { deleted: true },
        { deleted: false, reason: "ownership-mismatch" },
        { deleted: false, reason: "invalid-reference" },
      ]);
    });

  test("malicious attachment arrays cannot create unbounded Storage calls", () => {
    const plan = attachmentReferences({
      attachments: Array.from({ length: 100 }, (_, index) =>
        `gs://${BUCKET}/message_attachments/user-1/m1/${index}`),
    });
    assert.equal(plan.references.length, 8);
    assert.equal(plan.skipped, 92);
  });
});
