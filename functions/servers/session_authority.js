const {
  assertNotRestricted, fail, transactionGetAll,
} = require("../integrity/guards");
const { readBoundSessionAccess } = require("./authority");
const { canonicalDisplayName } = require("./documents");
const {
  assertRoomBinding, assertSessionBinding, authorityFingerprint, deriveSessionGrant,
  hasUnresolvedRevocationAttempt, participantForSession, recipientBinding, tokenRecipientId, validateRecipient,
} = require("./session_contract");

async function readSessionTokenAuthority({ db, transaction, uid, input, nowMs }) {
  const access = await readBoundSessionAccess({ db, transaction, uid, ...input });
  assertRoomBinding(access.room, access);
  assertSessionBinding(access.session, { ...input, roomId: access.roomReference.id });
  if (access.room.serverSessionCleanupId != null) {
    fail("failed-precondition", "The previous media session is still being closed.");
  }
  const participantReference = access.roomReference.collection("participants").doc(uid);
  const recipientReference = access.sessionReference.collection("tokenRecipients").doc(tokenRecipientId(uid));
  const [participantSnapshot, recipientSnapshot, restriction] = await transactionGetAll(
    transaction, participantReference, recipientReference, db.doc(`restrictions/${uid}`));
  assertNotRestricted(restriction, "Your", nowMs);
  const participant = participantForSession(participantSnapshot, access, uid);
  const participantName = canonicalDisplayName(access.profile);
  const grant = deriveSessionGrant(access, participant);
  const fingerprint = authorityFingerprint(access, participant, grant);
  const binding = recipientBinding(access, uid);
  const recipient = recipientSnapshot.exists ? validateRecipient(recipientSnapshot.data(), binding) : null;
  return { ...access, participant, participantReference, participantSnapshot, participantName,
    recipient, recipientReference, recipientSnapshot, binding, grant, fingerprint };
}

function requireIssuableRecipient(authority, nowMs) {
  const recipient = authority.recipient;
  if (!recipient) return 1;
  if (hasUnresolvedRevocationAttempt(recipient) || recipient.revocationState === "revoking" || recipient.reconnectAfterMillis > nowMs ||
      (recipient.revocationState === "active" && recipient.authorityFingerprint !== authority.fingerprint)) {
    fail("failed-precondition", "Previous media access is still being revoked. Retry after cleanup.");
  }
  return recipient.tokenEpoch;
}

module.exports = { readSessionTokenAuthority, requireIssuableRecipient };
