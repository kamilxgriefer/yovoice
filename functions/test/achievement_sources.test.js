const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const {
  adaptActiveDay,
  adaptClubMessageCreated,
  adaptCommunityJoined,
  adaptDirectMessageCreated,
  adaptMomentPublished,
  adaptReactionReceived,
  adaptRoomCreated,
  adaptRoomMessageCreated,
  adaptSocialMetricSnapshot,
  eventsWithActorActiveDay,
} = require("../achievements/sources");
const { eventFingerprint, eventIdFor } = require("../achievements/engine");

const AT = new Date("2026-08-16T23:59:59.000Z");

describe("canonical achievement source adapters", () => {
  test("direct messages derive sender and reject malformed conversation/message state", () => {
    const valid = {
      conversationId: "conversation-1",
      messageId: "message-1",
      message: {
        schemaVersion: 2,
        sequence: 1,
        conversationId: "conversation-1",
        senderId: "sender-1",
        type: "text",
        content: "hello",
        mediaUrl: null,
        durationSeconds: null,
        sentAt: AT,
        readBy: ["sender-1"],
        reactions: {},
        isDeleted: false,
        editedAt: null,
        replyToMessageId: null,
        replyToSenderId: null,
        replyToContent: null,
      },
      conversation: {
        schemaVersion: 2,
        participantIds: ["sender-1", "recipient-1"],
      },
      sourceCreatedAt: AT,
    };
    const event = adaptDirectMessageCreated(valid);
    assert.equal(event.beneficiaryId, "sender-1");
    assert.equal(event.metric, "messages");
    assert.equal(event.delta, 1);
    assert.equal(
      event.sourceKey,
      "conversations/conversation-1/messages/message-1",
    );

    assert.equal(adaptDirectMessageCreated({
      ...valid,
      conversation: { participantIds: ["recipient-1", "other-1"] },
    }), null);
    assert.equal(adaptDirectMessageCreated({
      ...valid,
      conversation: { participantIds: ["sender-1", "sender-1"] },
    }), null);
    assert.equal(adaptDirectMessageCreated({
      ...valid,
      message: { ...valid.message, isDeleted: true },
    }), null);
    assert.equal(adaptDirectMessageCreated({
      ...valid,
      message: { ...valid.message, type: "voice" },
    }), null);
    assert.equal(adaptDirectMessageCreated({
      ...valid,
      message: { ...valid.message, schemaVersion: 1 },
    }), null);
    assert.equal(adaptDirectMessageCreated({
      ...valid,
      message: { ...valid.message, conversationId: "another-conversation" },
    }), null);
    assert.equal(adaptDirectMessageCreated({
      ...valid,
      message: { ...valid.message, content: "x".repeat(2001) },
    }), null);
    assert.equal(adaptDirectMessageCreated({
      ...valid,
      message: { ...valid.message, sentAt: new Date(AT.getTime() - 300_001) },
    }), null);
    assert.equal(adaptDirectMessageCreated({
      ...valid,
      message: { ...valid.message, unexpected: true },
    }), null);

    const opaqueUid = " sender-1 ";
    const opaqueEvent = adaptDirectMessageCreated({
      ...valid,
      message: {
        ...valid.message,
        senderId: opaqueUid,
        readBy: [opaqueUid],
      },
      conversation: {
        schemaVersion: 2,
        participantIds: [opaqueUid, "recipient-1"],
      },
    });
    assert.equal(opaqueEvent.beneficiaryId, opaqueUid);
    assert.equal(opaqueEvent.actorId, opaqueUid);
  });

  test("Club messages require the canonical member and a writing role", () => {
    const input = {
      clubId: "club-1",
      channelId: "channel-1",
      messageId: "message-1",
      message: {
        clubId: "club-1",
        channelId: "channel-1",
        senderId: "member-1",
        senderName: "Member One",
        senderPhotoUrl: null,
        content: "hello club",
        sentAt: AT,
        editedAt: null,
        isDeleted: false,
      },
      club: { status: "active" },
      channel: { type: "chat" },
      member: { userId: "member-1", role: "member", banned: false },
      sourceCreatedAt: AT,
    };
    assert.equal(adaptClubMessageCreated(input).metric, "messages");
    assert.equal(adaptClubMessageCreated({
      ...input,
      member: { ...input.member, role: "guest" },
    }), null);
    assert.equal(adaptClubMessageCreated({
      ...input,
      member: { ...input.member, userId: "attacker" },
    }), null);
    assert.equal(adaptClubMessageCreated({
      ...input,
      message: { ...input.message, channelId: "other-channel" },
    }), null);
    assert.equal(adaptClubMessageCreated({
      ...input,
      club: { status: "suspended" },
    }), null);
    assert.equal(adaptClubMessageCreated({
      ...input,
      message: { ...input.message, unexpected: true },
    }), null);
  });

  test("Room message requires authority resolved outside the client payload", () => {
    const input = {
      roomId: "room-1",
      messageId: "message-1",
      message: {
        senderId: "speaker-1",
        senderName: "Speaker One",
        senderPhotoUrl: null,
        text: "hello",
        createdAt: AT,
        reactions: {},
      },
      room: { status: "active" },
      senderAuthorized: true,
      sourceCreatedAt: AT,
    };
    assert.equal(adaptRoomMessageCreated(input).beneficiaryId, "speaker-1");
    assert.equal(adaptRoomMessageCreated({ ...input, senderAuthorized: false }), null);
    assert.equal(adaptRoomMessageCreated({
      ...input,
      message: { ...input.message, text: "" },
    }), null);
    assert.equal(adaptRoomMessageCreated({
      ...input,
      room: { status: "closed" },
    }), null);
    assert.equal(adaptRoomMessageCreated({
      ...input,
      message: { ...input.message, reactions: { "👍": ["speaker-1"] } },
    }), null);
  });

  test("created Rooms exclude server-created Club lounges", () => {
    const input = {
      roomId: "room-1",
      room: { hostId: "host-1", roomType: "community" },
      sourceCreatedAt: AT,
    };
    assert.equal(adaptRoomCreated(input).metric, "rooms");
    assert.equal(adaptRoomCreated({
      ...input,
      room: { hostId: "host-1", roomType: "temporary" },
    }).metric, "rooms");
    assert.equal(adaptRoomCreated({
      ...input,
      room: { hostId: "host-1", roomType: "broadcast" },
    }), null);
    assert.equal(adaptRoomCreated({
      ...input,
      room: { ...input.room, roomKind: "clubLounge", clubId: "club-1" },
    }), null);
  });

  test("community lifetime keys distinguish Clubs and Rooms without counting lounges", () => {
    const club = adaptCommunityJoined({
      kind: "club",
      communityId: "community-1",
      userId: "user-1",
      sourceCreatedAt: AT,
    });
    const room = adaptCommunityJoined({
      kind: "room",
      communityId: "community-1",
      userId: "user-1",
      sourceCreatedAt: AT,
    });
    assert.notEqual(eventIdFor(club), eventIdFor(room));
    assert.equal(adaptCommunityJoined({
      kind: "room",
      communityId: "community-1",
      userId: "user-1",
      roomKind: "clubLounge",
    }), null);
  });

  test("Moment source is exactly one immutable-author false-to-true publication", () => {
    const momentId = "a".repeat(20);
    const common = {
      schemaVersion: 2,
      authorId: "author-1",
      authorName: "Author One",
      authorPhotoUrl: null,
      caption: "A moment",
      storagePath: `voice_moments/author-1/${momentId}.m4a`,
      durationSeconds: 30,
      likeCount: 0,
      commentCount: 0,
      replyToMomentId: null,
      isDeleted: false,
      createdAt: new Date(AT.getTime() - 60_000),
    };
    const input = {
      momentId,
      before: {
        ...common,
        audioUrl: null,
        isPublished: false,
        status: "uploading",
        mediaGeneration: null,
        mediaSize: null,
        mediaContentType: null,
        publishedAt: null,
        updatedAt: new Date(AT.getTime() - 60_000),
      },
      after: {
        ...common,
        audioUrl: "https://storage.example/moment.m4a",
        isPublished: true,
        status: "published",
        mediaGeneration: "123",
        mediaSize: 4096,
        mediaContentType: "audio/mp4",
        publishedAt: AT,
        updatedAt: AT,
      },
      storageObject: {
        name: `voice_moments/author-1/${momentId}.m4a`,
        contentType: "audio/mp4",
        size: "4096",
        generation: "123",
        metadata: {
          authorId: "author-1",
          momentId,
        },
      },
      sourceUpdatedAt: AT,
    };
    assert.equal(adaptMomentPublished(input).metric, "moments");
    assert.equal(adaptMomentPublished({
      ...input,
      before: { ...input.before, authorId: "other-author" },
    }), null);
    assert.equal(adaptMomentPublished({
      ...input,
      before: { ...input.before, isPublished: true },
    }), null);
    assert.equal(adaptMomentPublished({
      ...input,
      after: { ...input.after, storagePath: "voice_moments/forged.m4a" },
    }), null);
    assert.equal(adaptMomentPublished({
      ...input,
      storageObject: { ...input.storageObject, size: 1 },
    }), null);
  });

  test("reactions reward only another author and have a permanent reactor key", () => {
    const input = {
      kind: "directMessage",
      contentKey: "conversations/c/messages/m",
      reactorId: "reactor-1",
      authorId: "author-1",
      sourceCreatedAt: AT,
    };
    const first = adaptReactionReceived(input);
    const replayAfterEmojiChange = adaptReactionReceived(input);
    assert.equal(eventIdFor(first), eventIdFor(replayAfterEmojiChange));
    assert.equal(adaptReactionReceived({
      ...input,
      reactorId: "author-1",
    }), null);
    assert.equal(adaptReactionReceived({ ...input, contentDeleted: true }), null);
  });

  test("absolute social snapshots carry a monotonic version", () => {
    const current = adaptSocialMetricSnapshot({
      uid: "user-1",
      metric: "followers",
      value: 20,
      version: 3,
      actorId: "follower-1",
    });
    assert.equal(current.mode, "absolute");
    assert.equal(current.value, 20);
    assert.equal(adaptSocialMetricSnapshot({
      uid: "user-1",
      metric: "following",
      value: 20,
      version: 3,
    }), null);
  });

  test("many actions on one UTC day collapse to the same active-day event", () => {
    const first = adaptActiveDay({ uid: "user-1", occurredAt: AT });
    const sameDay = adaptActiveDay({
      uid: "user-1",
      occurredAt: new Date("2026-08-16T00:00:01.000Z"),
    });
    const nextDay = adaptActiveDay({
      uid: "user-1",
      occurredAt: new Date("2026-08-17T00:00:00.000Z"),
    });
    assert.equal(eventIdFor(first), eventIdFor(sameDay));
    assert.notEqual(eventIdFor(first), eventIdFor(nextDay));
    // Not only the id: the full canonical content must collapse too, or the
    // second event of a user-day becomes an unresolvable ledger collision
    // (2026-08-18 production incident).
    assert.equal(eventFingerprint(first), eventFingerprint(sameDay));
    assert.deepEqual(first.occurredAt, new Date("2026-08-16T00:00:00.000Z"));
    assert.deepEqual(sameDay.occurredAt, new Date("2026-08-16T00:00:00.000Z"));

    const receivedReaction = adaptReactionReceived({
      kind: "momentLike",
      contentKey: "voiceMoments/m",
      reactorId: "reactor-1",
      authorId: "author-1",
      sourceCreatedAt: AT,
    });
    const [, activeDay] = eventsWithActorActiveDay(receivedReaction, AT);
    assert.equal(activeDay.beneficiaryId, "reactor-1");
    assert.notEqual(activeDay.beneficiaryId, receivedReaction.beneficiaryId);
  });
});
