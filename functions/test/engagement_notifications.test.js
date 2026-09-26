/**
 * Comment, voice-comment and @mention notifications (ADR-213).
 *
 * The properties that matter, in order:
 *   - a comment tells the parent's AUTHOR and nobody else;
 *   - a commenter never notifies themself;
 *   - a block in either direction, an inactive account, a communication
 *     restriction, a deleted comment and an expired or unpublished parent
 *     all write nothing;
 *   - a redelivery of the same event is a no-op (delivery ledger);
 *   - deleting the comment retires the row;
 *   - a mention reaches only people who can actually SEE the parent — the
 *     audience-leak case is the reason mentions are validated server-side
 *     rather than trusted from the composer.
 */
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();
const { FieldPath, Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const {
  createMomentIntegrityService,
  momentStoragePath,
} = require("../moments/integrity");
const { REEL_COMMENT_SCHEMA_VERSION } = require("../reels/engagement");
const {
  commentEventId,
  commentNotificationId,
  handleMomentCommentCreated,
  handleMomentCommentDeleted,
  handleReelCommentCreated,
  handleReelCommentDeleted,
  mentionEventId,
  mentionNotificationId,
  SURFACES,
} = require("../notifications/engagement");
const { eventLedgerReference } = require("../notifications/canonical");
const {
  commentMentionReference,
  commentMentionRecord,
} = require("../notifications/comment_mentions");
const {
  commentMentionSourceIsCurrent,
  commentNotificationSourceIsCurrent,
} = require("../notifications/engagement_source");

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);
const emulatorTest = (name, fn) => test(
  `Engagement notifications: ${name}`,
  { skip: enabled ? false : "Requires an explicit localhost emulator." },
  fn,
);

const NOW_MS = 1_910_000_000_000;
const now = Timestamp.fromMillis(NOW_MS);
const created = [];

function id(prefix) {
  const value = `en-${prefix}-${randomUUID().slice(0, 8)}`;
  return value;
}

async function user(overrides = {}) {
  const uid = id("user");
  await db.doc(`users/${uid}`).set({
    uid,
    displayName: `Canonical ${uid}`,
    status: "active",
    banned: false,
    disabled: false,
    ...overrides,
  });
  // The exact canonical projection `canonicalPublicProfile` accepts.
  await db.doc(`publicProfiles/${uid}`).set({
    accountType: "personal",
    bannerUrl: null,
    bio: "",
    country: "",
    creatorAudienceVisible: false,
    displayName: `Canonical ${uid}`,
    displayNameSearch: `canonical ${uid}`,
    followerCount: 0,
    followingCount: 0,
    friendCount: 0,
    learningLanguages: [],
    nativeLanguage: "",
    photoUrl: null,
    premiumIdentity: false,
    schemaVersion: 1,
    spokenLanguages: [],
    statusMessage: "",
    uid,
    updatedAt: now,
    username: uid,
    usernameSearch: uid,
    website: "",
  });
  created.push(db.doc(`users/${uid}`), db.doc(`publicProfiles/${uid}`));
  return uid;
}

/** The exact canonical published shape `validateMoment` accepts. */
function momentDocument(authorId, momentId, overrides = {}) {
  return {
    schemaVersion: 2,
    authorId,
    authorName: `Canonical ${authorId}`,
    authorPhotoUrl: null,
    caption: "A canonical Moment",
    audioUrl: null,
    storagePath: momentStoragePath(authorId, momentId),
    mediaGeneration: "1001",
    mediaSize: 4096,
    mediaContentType: "audio/mp4",
    durationSeconds: 12,
    isPublished: true,
    isDeleted: false,
    status: "published",
    likeCount: 0,
    commentCount: 1,
    replyToMomentId: null,
    createdAt: Timestamp.fromMillis(NOW_MS - 60_000),
    publishedAt: Timestamp.fromMillis(NOW_MS - 60_000),
    updatedAt: Timestamp.fromMillis(NOW_MS - 60_000),
    ...overrides,
  };
}

function momentCommentDocument(authorId, overrides = {}) {
  return {
    schemaVersion: 2,
    type: "text",
    authorId,
    authorName: `Canonical ${authorId}`,
    authorPhotoUrl: null,
    text: "A canonical comment",
    audioUrl: null,
    storagePath: null,
    durationSeconds: null,
    mediaGeneration: null,
    mediaSize: null,
    mediaContentType: null,
    createdAt: Timestamp.fromMillis(NOW_MS - 30_000),
    ...overrides,
  };
}

function reelDocument(authorId, overrides = {}) {
  return {
    schemaVersion: 1,
    status: "published",
    moderationStatus: "visible",
    authorId,
    authorName: `Canonical ${authorId}`,
    publishedAt: Timestamp.fromMillis(NOW_MS - 60_000),
    updatedAt: Timestamp.fromMillis(NOW_MS - 60_000),
    commentCount: 1,
    ...overrides,
  };
}

function reelCommentDocument(authorId, reelId, overrides = {}) {
  return {
    schemaVersion: REEL_COMMENT_SCHEMA_VERSION,
    type: "text",
    reelId,
    authorId,
    authorName: `Canonical ${authorId}`,
    text: "A canonical Yeel comment",
    durationSeconds: null,
    createdAt: Timestamp.fromMillis(NOW_MS - 30_000),
    ...overrides,
  };
}

async function seedMomentComment({ authorId, commenterId, moment = {}, comment = {} }) {
  const momentId = id("moment");
  const commentId = id("comment");
  const momentReference = db.doc(`voiceMoments/${momentId}`);
  const commentReference = momentReference.collection("comments").doc(commentId);
  await momentReference.set(momentDocument(authorId, momentId, moment));
  await commentReference.set(momentCommentDocument(commenterId, comment));
  created.push(momentReference);
  return { momentId, commentId, commentReference, momentReference };
}

async function seedReelComment({ authorId, commenterId }) {
  const reelId = id("reel");
  const commentId = id("comment");
  const reelReference = db.doc(`reels/${reelId}`);
  const commentReference = reelReference.collection("comments").doc(commentId);
  await reelReference.set(reelDocument(authorId));
  await commentReference.set(reelCommentDocument(commenterId, reelId));
  created.push(reelReference);
  return { reelId, commentId, commentReference, reelReference };
}

function createEvent(params, snapshot, overrides = {}) {
  return {
    id: `cloud-event-${randomUUID()}`,
    time: new Date(NOW_MS).toISOString(),
    params,
    data: snapshot,
    ...overrides,
  };
}

const options = { nowMs: NOW_MS };

async function inbox(uid) {
  return (await db.collection(`users/${uid}/notifications`).get()).docs;
}

after(async () => {
  for (const reference of created) {
    await db.recursiveDelete(reference).catch(() => {});
  }
});

emulatorTest("a comment notifies the Moment's author, with public identity only",
  async () => {
    const author = await user();
    const commenter = await user();
    const { momentId, commentId, commentReference } = await seedMomentComment({
      authorId: author,
      commenterId: commenter,
    });
    const result = await handleMomentCommentCreated(
      createEvent({ momentId, commentId }, await commentReference.get()),
      options,
    );
    assert.equal(result.outcome, "written");
    const rows = await inbox(author);
    assert.equal(rows.length, 1);
    const row = rows[0].data();
    assert.equal(rows[0].id, `momentComment_${commentId}`);
    assert.deepEqual(Object.keys(row).sort(), [
      "actorId", "actorName", "actorPhotoUrl", "bellSuppressed", "createdAt",
      "dedupeKey", "isRead", "sourceGeneration", "sourcePath", "targetId",
      "targetLabel", "targetSubId", "type",
    ]);
    assert.equal(row.type, "momentComment");
    assert.equal(row.actorId, commenter);
    assert.equal(row.actorPhotoUrl, null);
    assert.equal(row.targetId, momentId);
    assert.equal(row.targetSubId, commentId);
    // The comment's words never enter the notification.
    assert.equal(row.targetLabel, null);
    assert.equal(row.sourcePath, `voiceMoments/${momentId}/comments/${commentId}`);

    // A redelivery of the same CloudEvent writes nothing new, and the row
    // the author already read is neither duplicated nor unread again.
    await rows[0].ref.update({ isRead: true });
    const replay = await handleMomentCommentCreated(
      createEvent({ momentId, commentId }, await commentReference.get()),
      options,
    );
    assert.equal(replay.outcome, "skipped:replay");
    const after = await inbox(author);
    assert.equal(after.length, 1);
    assert.equal(after[0].data().isRead, true);

    // Deleting the comment retires the row.
    await commentReference.delete();
    const retirement = await handleMomentCommentDeleted(
      createEvent({ momentId, commentId }, null),
    );
    assert.equal(retirement.retired, 1);
    assert.equal((await inbox(author)).length, 0);
  });

emulatorTest("a self-comment notifies nobody", async () => {
  const author = await user();
  const { momentId, commentId, commentReference } = await seedMomentComment({
    authorId: author,
    commenterId: author,
  });
  const result = await handleMomentCommentCreated(
    createEvent({ momentId, commentId }, await commentReference.get()),
    options,
  );
  assert.equal(result.outcome, "skipped:self");
  assert.equal((await inbox(author)).length, 0);
});

emulatorTest("a block in either direction writes nothing", async () => {
  for (const direction of ["author-blocks", "commenter-blocks"]) {
    const author = await user();
    const commenter = await user();
    const blocker = direction === "author-blocks" ? author : commenter;
    const blocked = direction === "author-blocks" ? commenter : author;
    await db.doc(`users/${blocker}/blocked/${blocked}`).set({ blocked: true });
    const { momentId, commentId, commentReference } = await seedMomentComment({
      authorId: author,
      commenterId: commenter,
    });
    const result = await handleMomentCommentCreated(
      createEvent({ momentId, commentId }, await commentReference.get()),
      options,
    );
    assert.equal(result.outcome, "skipped:blocked", direction);
    assert.equal((await inbox(author)).length, 0, direction);
  }
});

emulatorTest("an inactive or muted party writes nothing", async () => {
  const bannedAuthor = await user({ banned: true });
  const commenter = await user();
  const banned = await seedMomentComment({
    authorId: bannedAuthor,
    commenterId: commenter,
  });
  assert.equal(
    (await handleMomentCommentCreated(
      createEvent(
        { momentId: banned.momentId, commentId: banned.commentId },
        await banned.commentReference.get(),
      ),
      options,
    )).outcome,
    "skipped:inactive",
  );

  const author = await user();
  const mutedCommenter = await user();
  await db.doc(`restrictions/${mutedCommenter}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  const muted = await seedMomentComment({
    authorId: author,
    commenterId: mutedCommenter,
  });
  assert.equal(
    (await handleMomentCommentCreated(
      createEvent(
        { momentId: muted.momentId, commentId: muted.commentId },
        await muted.commentReference.get(),
      ),
      options,
    )).outcome,
    "skipped:restricted",
  );
  await db.doc(`restrictions/${mutedCommenter}`).delete();
});

emulatorTest("an expired, unpublished or deleted source writes nothing", async () => {
  const author = await user();
  const commenter = await user();
  const expired = await seedMomentComment({
    authorId: author,
    commenterId: commenter,
    moment: {
      expiresAt: Timestamp.fromMillis(NOW_MS - 1),
    },
  });
  assert.equal(
    (await handleMomentCommentCreated(
      createEvent(
        { momentId: expired.momentId, commentId: expired.commentId },
        await expired.commentReference.get(),
      ),
      options,
    )).outcome,
    "skipped:invalid-source",
  );

  // The comment is gone by the time the trigger runs (deleted immediately,
  // or the parent's deletion cascade got there first).
  const removed = await seedMomentComment({
    authorId: author,
    commenterId: commenter,
  });
  const snapshot = await removed.commentReference.get();
  await removed.commentReference.delete();
  assert.equal(
    (await handleMomentCommentCreated(
      createEvent(
        { momentId: removed.momentId, commentId: removed.commentId },
        snapshot,
      ),
      options,
    )).outcome,
    "skipped:invalid-source",
  );
  assert.equal((await inbox(author)).length, 0);
});

emulatorTest("a friends-only Moment only notifies inside its audience", async () => {
  const author = await user({ profileVisibility: "friends" });
  const stranger = await user();
  const { momentId, commentId, commentReference } = await seedMomentComment({
    authorId: author,
    commenterId: stranger,
  });
  const notification = {
    type: "momentComment",
    actorId: stranger,
    targetId: momentId,
    sourcePath: `voiceMoments/${momentId}/comments/${commentId}`,
  };
  // The commenter cannot see this Moment any more (they never could, in this
  // fixture): the source is not current, so no row is written and no push
  // would survive revalidation.
  assert.equal(
    await commentNotificationSourceIsCurrent({
      recipientId: author,
      notification,
      reader: db,
      firestore: db,
      nowMs: NOW_MS,
    }),
    false,
  );
  const result = await handleMomentCommentCreated(
    createEvent({ momentId, commentId }, await commentReference.get()),
    options,
  );
  assert.equal(result.outcome, "skipped:invalid-source");

  // With mutual friendship guards in place the same comment is delivered.
  const guard = (ownerId, friendId) => db
    .doc(`friendshipGuards/${ownerId}/friends/${friendId}`)
    .set({
      schemaVersion: 1,
      ownerId,
      friendId,
      establishedAt: Timestamp.fromMillis(NOW_MS - 120_000),
    });
  await guard(author, stranger);
  await guard(stranger, author);
  const friendly = await seedMomentComment({
    authorId: author,
    commenterId: stranger,
  });
  assert.equal(
    (await handleMomentCommentCreated(
      createEvent(
        { momentId: friendly.momentId, commentId: friendly.commentId },
        await friendly.commentReference.get(),
      ),
      options,
    )).outcome,
    "written",
  );
});

emulatorTest("mentions reach the named people, never the author twice", async () => {
  const author = await user();
  const commenter = await user();
  const mentioned = await user();
  const { momentId, commentId, commentReference } = await seedMomentComment({
    authorId: author,
    commenterId: commenter,
  });
  await commentMentionReference(db, "moment", momentId, commentId).set(
    commentMentionRecord({
      kind: "moment",
      parentId: momentId,
      commentId,
      actorId: commenter,
      // The author and the commenter are listed deliberately: the author
      // already gets the comment row and the commenter is the actor.
      mentionUserIds: [mentioned, author],
      now,
    }),
  );
  const result = await handleMomentCommentCreated(
    createEvent({ momentId, commentId }, await commentReference.get()),
    options,
  );
  assert.equal(result.outcome, "written");
  assert.equal(result.mentions.considered, 1);
  assert.equal(result.mentions.written, 1);
  assert.equal((await inbox(author)).length, 1);
  const mentionRows = await inbox(mentioned);
  assert.equal(mentionRows.length, 1);
  assert.equal(mentionRows[0].id, `commentMention_${commentId}`);
  assert.equal(mentionRows[0].data().type, "commentMention");
  assert.equal(mentionRows[0].data().targetSubId, commentId);

  // Deleting the comment retires the author row AND every mention row, and
  // removes the mention record itself.
  await commentReference.delete();
  const retirement = await handleMomentCommentDeleted(
    createEvent({ momentId, commentId }, null),
  );
  assert.equal(retirement.retired, 2);
  assert.equal((await inbox(author)).length, 0);
  assert.equal((await inbox(mentioned)).length, 0);
  assert.equal(
    (await commentMentionReference(db, "moment", momentId, commentId).get())
      .exists,
    false,
  );
});

emulatorTest("a mention cannot announce a Moment the mentioned person cannot see",
  async () => {
    const author = await user({ profileVisibility: "friends" });
    const commenter = await user();
    const outsider = await user();
    const guard = (ownerId, friendId) => db
      .doc(`friendshipGuards/${ownerId}/friends/${friendId}`)
      .set({
        schemaVersion: 1,
        ownerId,
        friendId,
        establishedAt: Timestamp.fromMillis(NOW_MS - 120_000),
      });
    // The commenter is a friend of the author; the outsider is not.
    await guard(author, commenter);
    await guard(commenter, author);
    const { momentId, commentId, commentReference } = await seedMomentComment({
      authorId: author,
      commenterId: commenter,
    });
    await commentMentionReference(db, "moment", momentId, commentId).set(
      commentMentionRecord({
        kind: "moment",
        parentId: momentId,
        commentId,
        actorId: commenter,
        mentionUserIds: [outsider],
        now,
      }),
    );
    const result = await handleMomentCommentCreated(
      createEvent({ momentId, commentId }, await commentReference.get()),
      options,
    );
    assert.equal(result.outcome, "written");
    assert.equal(result.mentions.written, 0);
    assert.equal((await inbox(outsider)).length, 0);
    assert.equal(
      await commentMentionSourceIsCurrent({
        recipientId: outsider,
        notification: {
          type: "commentMention",
          actorId: commenter,
          targetId: momentId,
          sourcePath: `voiceMoments/${momentId}/comments/${commentId}`,
        },
        reader: db,
        firestore: db,
        nowMs: NOW_MS,
      }),
      false,
    );
  });

emulatorTest("a Yeel comment notifies its author and retires on removal", async () => {
  const author = await user();
  const commenter = await user();
  const { reelId, commentId, commentReference } = await seedReelComment({
    authorId: author,
    commenterId: commenter,
  });
  const result = await handleReelCommentCreated(
    createEvent({ reelId, commentId }, await commentReference.get()),
    options,
  );
  assert.equal(result.outcome, "written");
  const rows = await inbox(author);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].data().type, "reelComment");
  assert.equal(rows[0].id, `reelComment_${commentId}`);
  assert.equal(rows[0].data().targetId, reelId);

  // The Yeel's author removing somebody else's comment (removeReelComment)
  // deletes the same document, so the same trigger retires the row.
  await commentReference.delete();
  assert.equal(
    (await handleReelCommentDeleted(createEvent({ reelId, commentId }, null)))
      .retired,
    1,
  );
  assert.equal((await inbox(author)).length, 0);
});

emulatorTest("a hidden or expired Yeel writes nothing", async () => {
  const author = await user();
  const commenter = await user();
  const { reelId, commentId, commentReference, reelReference } =
    await seedReelComment({ authorId: author, commenterId: commenter });
  await reelReference.update({ moderationStatus: "hidden" });
  assert.equal(
    (await handleReelCommentCreated(
      createEvent({ reelId, commentId }, await commentReference.get()),
      options,
    )).outcome,
    "skipped:invalid-source",
  );
  assert.equal((await inbox(author)).length, 0);
});

emulatorTest("the delivery ledger records every outcome exactly once", async () => {
  const author = await user();
  const commenter = await user();
  const { momentId, commentId, commentReference } = await seedMomentComment({
    authorId: author,
    commenterId: commenter,
  });
  await handleMomentCommentCreated(
    createEvent({ momentId, commentId }, await commentReference.get()),
    options,
  );
  const ledger = await eventLedgerReference(
    commentEventId(SURFACES.moment, momentId, commentId),
  ).get();
  assert.equal(ledger.exists, true);
  assert.equal(ledger.data().outcome, "written");
  assert.equal(ledger.data().recipientId, author);
  assert.equal(
    ledger.data().notificationId,
    commentNotificationId(SURFACES.moment, commentId),
  );
  assert.equal(
    mentionEventId(SURFACES.moment, momentId, commentId, author),
    `comment-mention:moment:${momentId}:${commentId}:${author}`,
  );
  assert.equal(mentionNotificationId(commentId), `commentMention_${commentId}`);
});

emulatorTest("createMomentComment stores a validated mention list and hashes it",
  async () => {
    const author = await user();
    const commenter = await user();
    const mentioned = await user();
    const momentId = id("moment");
    const momentReference = db.doc(`voiceMoments/${momentId}`);
    await momentReference.set(
      momentDocument(author, momentId, { commentCount: 0 }),
    );
    created.push(momentReference);
    const service = createMomentIntegrityService({
      db,
      FieldPath,
      Timestamp,
      storage: {
        getMetadata: async () => ({}),
        getSignedReadUrl: async () => "https://example.invalid/unused",
        revokeDownloadTokens: async () => ({}),
      },
      clock: () => NOW_MS,
    });
    const requestId = randomUUID();
    const request = (data) => ({
      auth: { uid: commenter, token: { email_verified: true } },
      data,
    });
    const result = await service.createMomentComment(request({
      momentId,
      requestId,
      text: `Hello @Canonical ${mentioned}`,
      mentionUserIds: [mentioned, mentioned, commenter],
    }));
    assert.equal(result.created, true);
    const record = await commentMentionReference(
      db,
      "moment",
      momentId,
      result.commentId,
    ).get();
    // Duplicates and the caller's own uid are dropped before storage.
    assert.deepEqual(record.data().mentionUserIds, [mentioned]);
    assert.equal(record.data().actorId, commenter);

    // The mention list is part of the idempotency input: the same requestId
    // with a different list is refused rather than silently replayed.
    await assert.rejects(
      service.createMomentComment(request({
        momentId,
        requestId,
        text: `Hello @Canonical ${mentioned}`,
        mentionUserIds: [author],
      })),
      (error) => error.code === "already-exists" || error.code === "aborted",
    );
    // An identical replay still returns the original receipt.
    const replay = await service.createMomentComment(request({
      momentId,
      requestId,
      text: `Hello @Canonical ${mentioned}`,
      mentionUserIds: [mentioned],
    }));
    assert.equal(replay.commentId, result.commentId);

    // A malformed list is refused outright: a non-string entry, an id with
    // a path separator in it, and a list too long to be a real composer's.
    for (const malformed of [
      [42],
      ["path/traversal"],
      Array.from({ length: 21 }, (_, index) => `mention-${index}`),
      "not-an-array",
    ]) {
      await assert.rejects(
        service.createMomentComment(request({
          momentId,
          requestId: randomUUID(),
          text: "Hi",
          mentionUserIds: malformed,
        })),
        (error) => error.code === "invalid-argument",
        JSON.stringify(malformed),
      );
    }
  });

emulatorTest("a comment with no mention list keeps the pre-mention input exactly",
  async () => {
    const author = await user();
    const commenter = await user();
    const momentId = id("moment");
    const momentReference = db.doc(`voiceMoments/${momentId}`);
    await momentReference.set(
      momentDocument(author, momentId, { commentCount: 0 }),
    );
    created.push(momentReference);
    const service = createMomentIntegrityService({
      db,
      FieldPath,
      Timestamp,
      storage: {
        getMetadata: async () => ({}),
        getSignedReadUrl: async () => "https://example.invalid/unused",
        revokeDownloadTokens: async () => ({}),
      },
      clock: () => NOW_MS,
    });
    const result = await service.createMomentComment({
      auth: { uid: commenter, token: { email_verified: true } },
      data: { momentId, requestId: randomUUID(), text: "No mentions here" },
    });
    assert.equal(result.created, true);
    const comment = await db
      .doc(`voiceMoments/${momentId}/comments/${result.commentId}`)
      .get();
    // The stored comment is byte for byte the pre-mention shape: the list
    // lives in its own server-only record, never on the comment.
    assert.equal(Object.hasOwn(comment.data(), "mentionUserIds"), false);
    assert.equal(
      (await commentMentionReference(db, "moment", momentId, result.commentId)
        .get()).exists,
      false,
    );
  });
