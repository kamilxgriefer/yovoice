const {
  digest,
  fail,
  requireBoolean,
  requireExactInput,
  requireId,
  requireRequestId,
  requireUid,
  timestampMillis,
} = require("../integrity/guards");
const {
  denied,
  readChannelAccess,
  validRevision,
} = require("./authority");
const { revision, text } = require("./contract");
const { canonicalDisplayName } = require("./documents");
const { createServerOperations } = require("./operations");

const QUESTION_STATUSES = Object.freeze(["queued", "onAir"]);
const MAX_QUESTION_LENGTH = 500;

function canonicalQuestionId(uid, requestId) {
  requireUid(uid);
  requireRequestId(requestId);
  return `pq_${digest("server.podcast.question.create.v1", uid, requestId).slice(0, 40)}`;
}

function questionInput(data, extras = []) {
  const fields = ["serverId", "channelId", "requestId", ...extras];
  requireExactInput(data, fields, fields);
  return {
    serverId: requireId(data.serverId, "serverId"),
    channelId: requireId(data.channelId, "channelId"),
    requestId: requireRequestId(data.requestId),
  };
}

function requirePodcastQuestionsChannel(access) {
  if (access.server.serverType !== "podcast" || access.channel.kind !== "questions") denied();
  return access;
}

function canonicalQuestion(snapshot, { serverId, channelId, questionId }) {
  if (!snapshot.exists) fail("not-found", "The selected question is unavailable.");
  const question = snapshot.data() ?? {};
  const createdAtMillis = timestampMillis(question.createdAt);
  const updatedAtMillis = timestampMillis(question.updatedAt);
  const onAirAtMillis = question.onAirAt === null ? null : timestampMillis(question.onAirAt);
  const onAirShape = question.status === "onAir"
    ? typeof question.onAirById === "string" && onAirAtMillis !== null
    : question.onAirById === null && question.onAirAt === null;
  if (question.schemaVersion !== 1 || question.serverId !== serverId ||
      question.channelId !== channelId || question.questionId !== questionId ||
      question.questionKind !== "podcastQuestion" ||
      !QUESTION_STATUSES.includes(question.status) || !onAirShape ||
      typeof question.authorId !== "string" || typeof question.authorName !== "string" ||
      typeof question.body !== "string" || question.body.length < 1 ||
      question.body.length > MAX_QUESTION_LENGTH || !validRevision(question.revision) ||
      !Number.isSafeInteger(question.voteCount) || question.voteCount < 0 ||
      question.voteCount >= Number.MAX_SAFE_INTEGER ||
      createdAtMillis === null || updatedAtMillis === null) {
    fail("data-loss", "The podcast question needs reconciliation.");
  }
  return question;
}

function canonicalVote(snapshot, { serverId, channelId, questionId, uid }) {
  if (!snapshot.exists) return null;
  const vote = snapshot.data() ?? {};
  if (vote.schemaVersion !== 1 || vote.serverId !== serverId ||
      vote.channelId !== channelId || vote.questionId !== questionId ||
      vote.userId !== uid || typeof vote.active !== "boolean" ||
      !validRevision(vote.questionRevision) || typeof vote.operationId !== "string" ||
      timestampMillis(vote.createdAt) === null || timestampMillis(vote.updatedAt) === null) {
    fail("data-loss", "The podcast question vote needs reconciliation.");
  }
  return vote;
}

function requireExpected(actual, expected) {
  if (actual !== expected) {
    fail("aborted", "This question changed. Refresh before retrying this action.");
  }
}

function createServerPodcastQuestionService(dependencies) {
  const { db, Timestamp } = dependencies;
  if (!db?.runTransaction || !Timestamp?.fromMillis) {
    throw new TypeError("db and Timestamp are required.");
  }
  const operations = createServerOperations(dependencies);

  async function createServerPodcastQuestionV1(request) {
    const input = questionInput(request.data, ["body"]);
    input.body = text(request.data.body, MAX_QUESTION_LENGTH, "body", 1);
    return operations.execute(
      request,
      "server.podcast.question.create.v1",
      input,
      async ({ transaction, auth, prior, now }) => {
        const access = requirePodcastQuestionsChannel(await readChannelAccess({
          db,
          transaction,
          uid: auth.uid,
          serverId: input.serverId,
          channelId: input.channelId,
          capability: "write",
        }));
        const questionId = canonicalQuestionId(auth.uid, input.requestId);
        const reference = access.channelReference.collection("questions").doc(questionId);
        const existing = await transaction.get(reference);
        if (prior) {
          const question = canonicalQuestion(existing, { ...input, questionId });
          if (question.revision === prior.revision && question.authorId === auth.uid) return prior;
          fail("aborted", "The question changed after the original request.");
        }
        if (existing.exists) {
          fail("data-loss", "A podcast question exists without its creation receipt.");
        }
        transaction.create(reference, {
          schemaVersion: 1,
          serverId: input.serverId,
          channelId: input.channelId,
          questionId,
          questionKind: "podcastQuestion",
          authorId: auth.uid,
          authorName: canonicalDisplayName(access.profile),
          body: input.body,
          status: "queued",
          voteCount: 0,
          revision: 1,
          onAirAt: null,
          onAirById: null,
          createdAt: now,
          updatedAt: now,
        });
        return {
          serverId: input.serverId,
          channelId: input.channelId,
          questionId,
          status: "queued",
          revision: 1,
        };
      },
    );
  }

  async function setServerPodcastQuestionVoteV1(request) {
    const input = questionInput(request.data, ["questionId", "expectedRevision", "voted"]);
    input.questionId = requireId(request.data.questionId, "questionId");
    input.expectedRevision = revision(request.data.expectedRevision, "expectedRevision");
    input.voted = requireBoolean(request.data.voted, "voted");
    return operations.execute(
      request,
      "server.podcast.question.vote.v1",
      input,
      async ({ transaction, auth, prior, now, identity }) => {
        const access = requirePodcastQuestionsChannel(await readChannelAccess({
          db,
          transaction,
          uid: auth.uid,
          serverId: input.serverId,
          channelId: input.channelId,
          capability: "write",
        }));
        const reference = access.channelReference.collection("questions").doc(input.questionId);
        const voteReference = reference.collection("votes").doc(auth.uid);
        const [questionSnapshot, voteSnapshot] = await Promise.all([
          transaction.get(reference),
          transaction.get(voteReference),
        ]);
        const question = canonicalQuestion(questionSnapshot, input);
        const existing = canonicalVote(voteSnapshot, { ...input, uid: auth.uid });
        if (prior) {
          if (existing?.operationId === identity.id && existing.active === prior.voted &&
              question.revision === prior.questionRevision) {
            return prior;
          }
          fail("aborted", "The vote changed after the original request.");
        }
        requireExpected(question.revision, input.expectedRevision);
        const wasVoted = existing?.active === true;
        const changed = wasVoted !== input.voted;
        let voteCount = question.voteCount;
        if (changed) voteCount += input.voted ? 1 : -1;
        if (!Number.isSafeInteger(voteCount) || voteCount < 0 ||
            voteCount >= Number.MAX_SAFE_INTEGER) {
          fail("data-loss", "The podcast question vote count needs reconciliation.");
        }
        if (changed) transaction.update(reference, { voteCount, updatedAt: now });
        transaction.set(voteReference, {
          schemaVersion: 1,
          serverId: input.serverId,
          channelId: input.channelId,
          questionId: input.questionId,
          userId: auth.uid,
          active: input.voted,
          questionRevision: question.revision,
          operationId: identity.id,
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
        });
        return {
          serverId: input.serverId,
          channelId: input.channelId,
          questionId: input.questionId,
          voted: input.voted,
          changed,
          voteCount,
          questionRevision: question.revision,
        };
      },
      { allowRestricted: !input.voted },
    );
  }

  async function setServerPodcastQuestionOnAirV1(request) {
    const input = questionInput(request.data, ["questionId", "expectedRevision", "onAir"]);
    input.questionId = requireId(request.data.questionId, "questionId");
    input.expectedRevision = revision(request.data.expectedRevision, "expectedRevision");
    input.onAir = requireBoolean(request.data.onAir, "onAir");
    return operations.execute(
      request,
      "server.podcast.question.on_air.v1",
      input,
      async ({ transaction, auth, prior, now }) => {
        const access = requirePodcastQuestionsChannel(await readChannelAccess({
          db,
          transaction,
          uid: auth.uid,
          serverId: input.serverId,
          channelId: input.channelId,
          capability: "moderate",
        }));
        const collection = access.channelReference.collection("questions");
        const reference = collection.doc(input.questionId);
        const [questionSnapshot, onAirSnapshot] = await Promise.all([
          transaction.get(reference),
          transaction.get(collection.where("status", "==", "onAir").limit(2)),
        ]);
        const question = canonicalQuestion(questionSnapshot, input);
        const current = onAirSnapshot.docs.map((document) => canonicalQuestion(
          document,
          { ...input, questionId: document.id },
        ));
        if (current.length > 1) {
          fail("data-loss", "More than one podcast question is marked on air.");
        }
        if (prior) {
          const expectedStatus = prior.onAir ? "onAir" : "queued";
          if (question.status === expectedStatus && question.revision === prior.revision) return prior;
          fail("aborted", "The on-air question changed after the original request.");
        }
        requireExpected(question.revision, input.expectedRevision);
        const currentlyOnAir = current[0] ?? null;
        if (input.onAir && question.status === "onAir") {
          if (currentlyOnAir?.questionId !== question.questionId) {
            fail("data-loss", "The podcast on-air state needs reconciliation.");
          }
          return {
            serverId: input.serverId,
            channelId: input.channelId,
            questionId: input.questionId,
            onAir: true,
            changed: false,
            revision: question.revision,
            previousQuestionId: null,
          };
        }
        if (!input.onAir && question.status === "queued") {
          return {
            serverId: input.serverId,
            channelId: input.channelId,
            questionId: input.questionId,
            onAir: false,
            changed: false,
            revision: question.revision,
            previousQuestionId: null,
          };
        }
        let previousQuestionId = null;
        if (input.onAir && currentlyOnAir && currentlyOnAir.questionId !== input.questionId) {
          previousQuestionId = currentlyOnAir.questionId;
          const previousRevision = currentlyOnAir.revision + 1;
          if (!validRevision(previousRevision)) {
            fail("data-loss", "The previous podcast question revision is exhausted.");
          }
          transaction.update(collection.doc(currentlyOnAir.questionId), {
            status: "queued",
            revision: previousRevision,
            onAirAt: null,
            onAirById: null,
            updatedAt: now,
          });
        }
        const nextRevision = question.revision + 1;
        if (!validRevision(nextRevision)) {
          fail("data-loss", "The podcast question revision is exhausted.");
        }
        transaction.update(reference, {
          status: input.onAir ? "onAir" : "queued",
          revision: nextRevision,
          onAirAt: input.onAir ? now : null,
          onAirById: input.onAir ? auth.uid : null,
          updatedAt: now,
        });
        return {
          serverId: input.serverId,
          channelId: input.channelId,
          questionId: input.questionId,
          onAir: input.onAir,
          changed: true,
          revision: nextRevision,
          previousQuestionId,
        };
      },
      { allowRestricted: !input.onAir },
    );
  }

  return {
    createServerPodcastQuestionV1,
    setServerPodcastQuestionVoteV1,
    setServerPodcastQuestionOnAirV1,
  };
}

module.exports = {
  MAX_QUESTION_LENGTH,
  QUESTION_STATUSES,
  canonicalQuestionId,
  createServerPodcastQuestionService,
};
