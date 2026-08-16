const {
  canonicalPublicProfile,
  digest,
  fail,
  isValidOpaqueUid,
  nonNegativeCount,
  requireId,
  requireSafeInteger,
  timestampMillis,
} = require("../integrity/guards");
const {
  momentStoragePath,
  validateStoredAudio,
  voiceReplyStoragePath,
} = require("./integrity");

function timestampOr(value, fallback) {
  return timestampMillis(value) === null ? fallback : value;
}

function valuesEqual(left, right) {
  if (left === right) return true;
  const leftMs = timestampMillis(left);
  const rightMs = timestampMillis(right);
  if (leftMs !== null || rightMs !== null) return leftMs === rightMs;
  if (Array.isArray(left) || Array.isArray(right)) {
    return Array.isArray(left) && Array.isArray(right) &&
      left.length === right.length &&
      left.every((value, index) => valuesEqual(value, right[index]));
  }
  if (left && right && typeof left === "object" && typeof right === "object") {
    const leftKeys = Object.keys(left).sort();
    const rightKeys = Object.keys(right).sort();
    return leftKeys.length === rightKeys.length &&
      leftKeys.every((key, index) => key === rightKeys[index] &&
        valuesEqual(left[key], right[key]));
  }
  return false;
}

function sameUpdateTime(snapshot, expected) {
  if (!snapshot?.exists || !expected) return false;
  return typeof snapshot.updateTime?.isEqual === "function"
    ? snapshot.updateTime.isEqual(expected)
    : timestampMillis(snapshot.updateTime) === timestampMillis(expected);
}

function createMomentMigrationService({
  db,
  FieldPath,
  Timestamp,
  storage,
  clock = () => Date.now(),
  beforeApply = null,
}) {
  if (!db || !FieldPath?.documentId || !Timestamp?.fromMillis ||
      !storage?.getMetadata || !storage?.getDownloadUrl) {
    throw new TypeError("db, FieldPath, Timestamp and storage are required.");
  }
  if (beforeApply !== null && typeof beforeApply !== "function") {
    throw new TypeError("beforeApply must be a function.");
  }

  function now() {
    const value = clock();
    if (!Number.isSafeInteger(value) || value < 0) {
      throw new TypeError("clock must return epoch milliseconds.");
    }
    return Timestamp.fromMillis(value);
  }

  async function canonicalMedia(path, expected) {
    try {
      const metadata = await storage.getMetadata(path);
      const generation = String(metadata.generation ?? "");
      const media = validateStoredAudio(metadata, expected, generation);
      const audioUrl = await storage.getDownloadUrl(path, metadata);
      if (typeof audioUrl !== "string" || !audioUrl || audioUrl.length > 4096) {
        return { issue: "missingCanonicalDownloadUrl" };
      }
      return { ...media, audioUrl };
    } catch (error) {
      return { issue: `invalidCanonicalMedia:${error.code ?? error.message}` };
    }
  }

  async function inspectMoment({ momentId, maxRelated = 200 }) {
    requireId(momentId, "momentId");
    requireSafeInteger(maxRelated, "maxRelated", { min: 1, max: 200 });
    const rootRef = db.doc(`voiceMoments/${momentId}`);
    const root = await rootRef.get();
    if (!root.exists) return { momentId, status: "missing", issues: ["missing"] };
    const data = root.data() ?? {};
    const issues = [];
    if (!isValidOpaqueUid(data.authorId)) {
      return { momentId, status: "conflict", issues: ["invalidAuthorId"] };
    }
    const authorId = data.authorId;
    const expectedPath = momentStoragePath(authorId, momentId);
    if (data.storagePath !== expectedPath) issues.push("invalidMomentStoragePath");
    if (!Number.isSafeInteger(data.durationSeconds) || data.durationSeconds < 1 ||
        data.durationSeconds > 60) issues.push("invalidMomentDuration");
    if (typeof data.caption !== "string" || data.caption.length > 280) {
      issues.push("invalidMomentCaption");
    }
    if (typeof data.isPublished !== "boolean") issues.push("invalidPublishState");
    if (data.replyToMomentId !== null && data.replyToMomentId !== undefined) {
      issues.push("unexpectedRootReplyLink");
    }
    try {
      nonNegativeCount(data.likeCount ?? 0, "legacy likeCount");
      nonNegativeCount(data.commentCount ?? 0, "legacy commentCount");
    } catch (_) {
      issues.push("invalidLegacyCounters");
    }
    const [profile, publicProfile, comments, likes] = await Promise.all([
      db.doc(`users/${authorId}`).get(),
      db.doc(`publicProfiles/${authorId}`).get(),
      rootRef.collection("comments").limit(maxRelated + 1).get(),
      rootRef.collection("likes").limit(maxRelated + 1).get(),
    ]);
    if (!profile.exists) issues.push("missingAuthorProfile");
    if (comments.size > maxRelated) issues.push("commentMigrationLimitExceeded");
    if (likes.size > maxRelated) issues.push("likeMigrationLimitExceeded");
    let canonicalIdentity = { displayName: "YO Voice user", photoUrl: null };
    try {
      canonicalIdentity = canonicalPublicProfile(publicProfile, authorId);
    } catch (_) {
      issues.push("invalidAuthorPublicProfile");
    }

    let rootMedia = {
      audioUrl: null,
      generation: null,
      size: null,
      contentType: null,
    };
    if (data.isPublished === true && data.isDeleted !== true) {
      rootMedia = await canonicalMedia(
        expectedPath,
        { authorId, momentId },
      );
      if (rootMedia.issue) issues.push(`momentMedia:${rootMedia.issue}`);
    } else if (data.audioUrl !== null && data.audioUrl !== undefined) {
      issues.push("unpublishedMomentHasAudioUrl");
    }

    const commentAuthorIds = [...new Set(comments.docs
      .map((comment) => comment.data()?.authorId)
      .filter((uid) => isValidOpaqueUid(uid)))];
    const commentProfiles = commentAuthorIds.length === 0
      ? []
      : await db.getAll(...commentAuthorIds.map((uid) =>
        db.doc(`publicProfiles/${uid}`)));
    const commentIdentityById = new Map();
    for (const snapshot of commentProfiles) {
      try {
        commentIdentityById.set(
          snapshot.id,
          canonicalPublicProfile(snapshot, snapshot.id),
        );
      } catch (_) {
        issues.push(`invalidCommentPublicProfile:${snapshot.id}`);
      }
    }
    const canonicalComments = [];
    for (const comment of comments.docs.slice(0, maxRelated)) {
      const commentData = comment.data() ?? {};
      const commentIssues = [];
      if (!isValidOpaqueUid(commentData.authorId)) {
        commentIssues.push("invalidAuthor");
      }
      if (!["text", "voice"].includes(commentData.type)) {
        commentIssues.push("invalidType");
      }
      if (typeof commentData.text !== "string" ||
          commentData.text.length > (commentData.type === "voice" ? 140 : 1000) ||
          (commentData.type === "text" && commentData.text.length === 0)) {
        commentIssues.push("invalidText");
      }
      if (timestampMillis(commentData.createdAt) === null) {
        commentIssues.push("invalidCreatedAt");
      }
      let media = {
        audioUrl: null,
        generation: null,
        size: null,
        contentType: null,
      };
      let storagePath = null;
      let durationSeconds = null;
      if (commentData.type === "voice" && commentIssues.length === 0) {
        if (!/^[A-Za-z0-9]{20}$/u.test(comment.id)) {
          commentIssues.push("invalidVoiceCommentId");
        } else {
          storagePath = voiceReplyStoragePath(
            commentData.authorId,
            momentId,
            comment.id,
          );
          if (commentData.storagePath !== storagePath) {
            commentIssues.push("invalidStoragePath");
          }
          if (!Number.isSafeInteger(commentData.durationSeconds) ||
              commentData.durationSeconds < 1 ||
              commentData.durationSeconds > 60) {
            commentIssues.push("invalidDuration");
          } else {
            durationSeconds = commentData.durationSeconds;
          }
          if (commentIssues.length === 0) {
            media = await canonicalMedia(
              storagePath,
              { authorId: commentData.authorId, commentId: comment.id, momentId },
            );
            if (media.issue) commentIssues.push(`media:${media.issue}`);
          }
        }
      }
      issues.push(...commentIssues.map((issue) =>
        `comment:${comment.id}:${issue}`));
      const commentIdentity = commentIdentityById.get(commentData.authorId) ?? {
        displayName: "YO Voice user",
        photoUrl: null,
      };
      canonicalComments.push({
        ref: comment.ref,
        sourceData: commentData,
        sourceUpdateTime: comment.updateTime,
        data: {
          schemaVersion: 2,
          type: commentData.type,
          authorId: commentData.authorId,
          authorName: commentIdentity.displayName,
          authorPhotoUrl: commentIdentity.photoUrl,
          text: commentData.text,
          audioUrl: media.audioUrl,
          storagePath,
          durationSeconds,
          mediaGeneration: media.generation,
          mediaSize: media.size,
          mediaContentType: media.contentType,
          createdAt: commentData.createdAt,
        },
      });
    }

    const canonicalLikes = [];
    for (const like of likes.docs.slice(0, maxRelated)) {
      const likeData = like.data() ?? {};
      if (!isValidOpaqueUid(like.id) || likeData.userId !== like.id) {
        issues.push(`like:${like.id}:invalidIdentity`);
        continue;
      }
      canonicalLikes.push({
        ref: like.ref,
        sourceData: likeData,
        sourceUpdateTime: like.updateTime,
        data: {
          schemaVersion: 1,
          userId: like.id,
          momentId,
          createdAt: timestampOr(likeData.createdAt, now()),
        },
      });
    }
    const generatedAt = now();
    const canonicalRoot = {
      schemaVersion: 2,
      authorId,
      authorName: canonicalIdentity.displayName,
      authorPhotoUrl: canonicalIdentity.photoUrl,
      caption: data.caption,
      audioUrl: rootMedia.audioUrl,
      storagePath: expectedPath,
      durationSeconds: data.durationSeconds,
      likeCount: canonicalLikes.length,
      commentCount: canonicalComments.length,
      replyToMomentId: null,
      isPublished: data.isDeleted === true ? false : data.isPublished === true,
      isDeleted: data.isDeleted === true,
      status: data.isDeleted === true
        ? "deleting"
        : data.isPublished === true
          ? "published"
          : "uploading",
      mediaGeneration: rootMedia.generation,
      mediaSize: rootMedia.size,
      mediaContentType: rootMedia.contentType,
      createdAt: timestampOr(data.createdAt, generatedAt),
      updatedAt: timestampOr(data.updatedAt, generatedAt),
      publishedAt: data.isPublished === true && data.isDeleted !== true
        ? timestampOr(data.publishedAt, timestampOr(data.updatedAt, generatedAt))
        : null,
    };
    const needsMigration = !valuesEqual(data, canonicalRoot) ||
      canonicalComments.some((comment) =>
        !valuesEqual(comment.sourceData, comment.data)) ||
      canonicalLikes.some((like) => !valuesEqual(like.sourceData, like.data));
    const uniqueIssues = [...new Set(issues)].sort();
    return {
      momentId,
      authorId,
      sourceUpdateTime: root.updateTime,
      status: uniqueIssues.length > 0
        ? "conflict"
        : needsMigration
          ? "ready"
          : "alreadyMigrated",
      issues: uniqueIssues,
      canonicalRoot,
      canonicalComments,
      canonicalLikes,
      commentCount: canonicalComments.length,
      likeCount: canonicalLikes.length,
    };
  }

  async function migrateMoment({ momentId, dryRun = true, maxRelated = 200 }) {
    const inspection = await inspectMoment({ momentId, maxRelated });
    const result = {
      momentId,
      status: inspection.status,
      issues: inspection.issues,
      commentCount: inspection.commentCount ?? 0,
      likeCount: inspection.likeCount ?? 0,
      dryRun,
    };
    if (dryRun || inspection.status === "missing" ||
        inspection.status === "alreadyMigrated") return result;
    if (inspection.status === "conflict") {
      const conflictId = digest("moment-migration-conflict", momentId);
      const conflictRef = db.doc(`momentMigrationConflicts/${conflictId}`);
      await db.runTransaction(async (transaction) => {
        const existing = await transaction.get(conflictRef);
        if (existing.exists) {
          const stored = existing.data() ?? {};
          if (stored.momentId !== momentId ||
              stored.authorId !== (inspection.authorId ?? null) ||
              !valuesEqual(stored.issues, inspection.issues.slice(0, 100))) {
            fail("data-loss", "The migration conflict ledger is inconsistent.");
          }
          return;
        }
        transaction.create(conflictRef, {
          schemaVersion: 1,
          momentId,
          authorId: inspection.authorId ?? null,
          issues: inspection.issues.slice(0, 100),
          status: "open",
          detectedAt: now(),
        });
      });
      return { ...result, conflictId };
    }
    const rootRef = db.doc(`voiceMoments/${momentId}`);
    if (beforeApply) await beforeApply({ inspection });
    await db.runTransaction(async (transaction) => {
      const [current, currentComments, currentLikes] = await Promise.all([
        transaction.get(rootRef),
        transaction.get(rootRef.collection("comments").limit(maxRelated + 1)),
        transaction.get(rootRef.collection("likes").limit(maxRelated + 1)),
      ]);
      if (!sameUpdateTime(current, inspection.sourceUpdateTime)) {
        fail("aborted", "The Voice Moment changed during migration.");
      }
      const expectedComments = new Map(inspection.canonicalComments.map(
        (comment) => [comment.ref.id, comment],
      ));
      const expectedLikes = new Map(inspection.canonicalLikes.map(
        (like) => [like.ref.id, like],
      ));
      if (currentComments.size !== expectedComments.size ||
          currentLikes.size !== expectedLikes.size) {
        fail("aborted", "Voice Moment children changed during migration.");
      }
      for (const document of currentComments.docs) {
        const expected = expectedComments.get(document.id);
        if (!expected || !sameUpdateTime(document, expected.sourceUpdateTime)) {
          fail("aborted", "Voice Moment comments changed during migration.");
        }
      }
      for (const document of currentLikes.docs) {
        const expected = expectedLikes.get(document.id);
        if (!expected || !sameUpdateTime(document, expected.sourceUpdateTime)) {
          fail("aborted", "Voice Moment likes changed during migration.");
        }
      }
      for (const comment of inspection.canonicalComments) {
        transaction.set(comment.ref, comment.data);
      }
      for (const like of inspection.canonicalLikes) {
        transaction.set(like.ref, like.data);
      }
      transaction.set(rootRef, inspection.canonicalRoot);
    });
    return { ...result, status: "migrated" };
  }

  async function scanMomentMigration({
    limit = 50,
    cursor = null,
    maxRelated = 200,
  } = {}) {
    requireSafeInteger(limit, "limit", { min: 1, max: 100 });
    if (cursor !== null) requireId(cursor, "cursor");
    let query = db.collection("voiceMoments")
      .orderBy(FieldPath.documentId())
      .limit(limit);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    const results = [];
    for (const document of snapshot.docs) {
      const inspected = await inspectMoment({
        momentId: document.id,
        maxRelated,
      });
      results.push({
        momentId: document.id,
        status: inspected.status,
        issues: inspected.issues.slice(0, 20),
        issueCount: inspected.issues.length,
        commentCount: inspected.commentCount ?? 0,
        likeCount: inspected.likeCount ?? 0,
      });
    }
    return {
      results,
      nextCursor: snapshot.docs.at(-1)?.id ?? null,
      hasMore: snapshot.size === limit,
    };
  }

  return { inspectMoment, migrateMoment, scanMomentMigration };
}

module.exports = { createMomentMigrationService };
