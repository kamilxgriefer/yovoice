const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const {
  parseStorageObjectReference,
  clubMediaPaths,
  voiceMomentMediaPaths,
  deleteExactPaths,
  cleanupRoomMedia,
  cleanupFamilyMedia,
} = require("../media/cleanup");

const BUCKET = "yovoice-test.firebasestorage.app";

describe("media lifecycle cleanup", () => {
  test("parser accepts only canonical references in the configured bucket", () => {
    assert.equal(
      parseStorageObjectReference(`gs://${BUCKET}/clubs/u1/c1/avatar`, BUCKET),
      "clubs/u1/c1/avatar",
    );
    assert.equal(
      parseStorageObjectReference(
        `https://firebasestorage.googleapis.com/v0/b/${BUCKET}` +
          "/o/clubs%2Fu1%2Fc1%2Fbanner?alt=media&token=x",
        BUCKET,
      ),
      "clubs/u1/c1/banner",
    );
    for (const malicious of [
      "clubs/u1/c1/avatar",
      "gs://other-bucket/clubs/u1/c1/avatar",
      `gs://${BUCKET}/clubs/u1/c1/%2e%2e/avatar`,
      `https://example.invalid/v0/b/${BUCKET}/o/clubs%2Fu1%2Fc1%2Favatar`,
      `https://firebasestorage.googleapis.com/v0/b/${BUCKET}` +
        "/o/clubs%252Fu1%252Fc1%252Favatar",
    ]) {
      assert.equal(parseStorageObjectReference(malicious, BUCKET), null);
    }
  });

  test("Club cleanup accepts only exact media bound to the same club", () => {
    const paths = clubMediaPaths({
      clubId: "club-1",
      bucketName: BUCKET,
      club: {
        avatarUrl: `gs://${BUCKET}/clubs/former-owner/club-1/avatar`,
        bannerUrl: `gs://${BUCKET}/clubs/victim/other-club/banner`,
      },
    });
    assert.deepEqual(paths, ["clubs/former-owner/club-1/avatar"]);
  });

  test("Club cleanup preserves legacy imageUrl compatibility", () => {
    assert.deepEqual(
      clubMediaPaths({
        clubId: "club-legacy",
        bucketName: BUCKET,
        club: {
          imageUrl:
            `gs://${BUCKET}/clubs/original-owner/club-legacy/avatar`,
        },
      }),
      ["clubs/original-owner/club-legacy/avatar"],
    );
  });

  test("Moment cleanup trusts only exact author/moment/comment storage paths", () => {
    const paths = voiceMomentMediaPaths({
      momentId: "moment-1",
      moment: {
        authorId: "author-1",
        storagePath: "voice_moments/author-1/moment-1.m4a",
      },
      comments: [
        {
          id: "comment-1",
          data: {
            authorId: "reply-author",
            storagePath:
              "voice_replies/reply-author/moment-1/comment-1.m4a",
          },
        },
        {
          id: "comment-2",
          data: {
            authorId: "attacker",
            storagePath: "voice_moments/victim/valuable.m4a",
          },
        },
      ],
    });
    assert.deepEqual(paths, [
      "voice_moments/author-1/moment-1.m4a",
      "voice_replies/reply-author/moment-1/comment-1.m4a",
    ]);
  });

  test("exact deletion is bounded, deduplicated and best-effort", async () => {
    const deleted = [];
    const bucket = {
      file(objectPath) {
        return {
          async delete(options) {
            assert.deepEqual(options, { ignoreNotFound: true });
            if (objectPath === "voice_moments/u/fail.m4a") {
              const error = new Error("nope");
              error.code = "storage-error";
              throw error;
            }
            deleted.push(objectPath);
          },
        };
      },
    };
    const outcome = await deleteExactPaths([
      "voice_moments/u/ok.m4a",
      "voice_moments/u/ok.m4a",
      "../victim",
      "voice_moments/u/fail.m4a",
    ], bucket);
    assert.deepEqual(deleted, ["voice_moments/u/ok.m4a"]);
    assert.deepEqual(outcome, [
      { objectPath: "voice_moments/u/ok.m4a", deleted: true },
      {
        objectPath: "voice_moments/u/fail.m4a",
        deleted: false,
        reason: "storage-error",
      },
    ]);
  });

  test("Room and Family cleanup derive bounded prefixes, never caller paths", async () => {
    const calls = [];
    const bucket = {
      async deleteFiles(options) {
        calls.push(options);
      },
    };
    await cleanupRoomMedia({ roomId: "room-1", bucket });
    await cleanupFamilyMedia({ clubId: "family_owner", bucket });
    assert.deepEqual(calls, [
      { prefix: "room_images/room-1/", force: true },
      { prefix: "family_moments/family_owner/", force: true },
    ]);
    await assert.rejects(
      cleanupRoomMedia({ roomId: "../../users", bucket }),
      /Invalid roomId/u,
    );
  });
});
