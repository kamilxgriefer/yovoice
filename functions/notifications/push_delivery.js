// Pure, dependency-free delivery limits shared by the Firestore trigger and
// its tests. FCM accepts at most 500 registration tokens per multicast call;
// keeping the boundary here makes that invariant impossible to bypass when
// the trigger grows new notification types.

const FCM_MULTICAST_LIMIT = 500;
const MAX_ACTIVE_FCM_TOKENS_PER_USER = 20;
const MAX_FCM_TOKEN_DOCUMENT_READS = 500;
const FIRESTORE_CLEANUP_BATCH_SIZE = 450;

const STALE_TOKEN_CODES = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

function chunks(values, size) {
  if (!Number.isInteger(size) || size < 1) {
    throw new TypeError("A positive chunk size is required.");
  }
  const result = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

/**
 * Drops every registration written before the account's session epoch
 * (`users/{uid}.authSessionEpoch`, seconds). The epoch is written when a
 * pre-registered account takeover is remediated (auth/federated_takeover.js);
 * the rules refuse any registration from a session older than it, and every
 * registration's `updatedAt` is the server's request time, so a document
 * older than the epoch was planted by a session that has been ended. It
 * receives nothing while the bounded purge is still working through it.
 * Accounts without an epoch are unaffected.
 */
function registrationsNotBeforeEpoch(documents, sessionEpoch) {
  if (!Number.isSafeInteger(sessionEpoch)) return documents;
  const epochMillis = sessionEpoch * 1000;
  return documents.filter((document) => {
    const writtenAt = typeof document?.get === "function"
      ? document.get("updatedAt")
      : document?.data?.()?.updatedAt;
    return typeof writtenAt?.toMillis === "function" &&
      writtenAt.toMillis() >= epochMillis;
  });
}

/**
 * Selects the bounded, newest token set used for delivery. The production
 * query is ordered by the Rules-enforced server timestamp, so the first
 * documents are the account's most recently active devices. Everything
 * beyond the cap is cleanup work, never a delivery target.
 */
function planTokenDocuments(documents) {
  const usable = [];
  const invalidReferences = [];
  const seen = new Set();

  for (const document of documents.slice(0, MAX_FCM_TOKEN_DOCUMENT_READS)) {
    const token = typeof document?.id === "string" ? document.id.trim() : "";
    if (!token || seen.has(token)) {
      if (document?.ref) invalidReferences.push(document.ref);
      continue;
    }
    seen.add(token);
    usable.push({ token, ref: document.ref });
  }

  return {
    tokens: usable
      .slice(0, MAX_ACTIVE_FCM_TOKENS_PER_USER)
      .map(({ token }) => token),
    tokenReferences: new Map(usable.map(({ token, ref }) => [token, ref])),
    overflowReferences: [
      ...usable
        .slice(MAX_ACTIVE_FCM_TOKENS_PER_USER)
        .map(({ ref }) => ref)
        .filter(Boolean),
      ...invalidReferences,
    ],
  };
}

/**
 * Sends every supplied token without ever crossing FCM's 500-token limit.
 * A whole-chunk transport failure is isolated so later chunks are still
 * attempted; individual permanent token failures are returned for cleanup.
 */
async function sendMulticastInChunks({ tokens, messaging, buildMessage }) {
  const staleTokens = new Set();
  const failures = [];
  const batchErrors = [];
  let attempted = 0;
  let successCount = 0;

  for (const tokenChunk of chunks(tokens, FCM_MULTICAST_LIMIT)) {
    attempted += tokenChunk.length;
    try {
      const response = await messaging.sendEachForMulticast(
        buildMessage(tokenChunk),
      );
      const responses = Array.isArray(response?.responses)
        ? response.responses
        : [];
      for (let index = 0; index < tokenChunk.length; index += 1) {
        const result = responses[index];
        if (result?.success === true) {
          successCount += 1;
          continue;
        }
        const code = result?.error?.code ?? "messaging/unknown-error";
        if (STALE_TOKEN_CODES.has(code)) {
          staleTokens.add(tokenChunk[index]);
        } else {
          failures.push({ code });
        }
      }
    } catch (error) {
      batchErrors.push({
        code: typeof error?.code === "string" ? error.code : "unknown",
        tokenCount: tokenChunk.length,
      });
    }
  }

  return {
    attempted,
    successCount,
    staleTokens: [...staleTokens],
    failures,
    batchErrors,
  };
}

module.exports = {
  FCM_MULTICAST_LIMIT,
  FIRESTORE_CLEANUP_BATCH_SIZE,
  MAX_ACTIVE_FCM_TOKENS_PER_USER,
  MAX_FCM_TOKEN_DOCUMENT_READS,
  chunks,
  planTokenDocuments,
  registrationsNotBeforeEpoch,
  sendMulticastInChunks,
};
